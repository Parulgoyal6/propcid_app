// screens/influencer/influencer_video_form_screen.dart
//
// Create or edit one influencer video — the mobile form for
// `InfluencerVideoModal.tsx`.
//
// WHAT THE PORTAL'S MODAL DOES, AND WHERE THIS DIFFERS
// ---------------------------------------------------
// Same four fields (title, description, video type, hashtags), same two files
// (video, optional thumbnail), same two gates before submit — "Please upload a
// video file" when creating without one, and "Please fill in all required fields"
// when title or type is missing (:112-118). Same write: `approval_status:
// 'pending'` on create *and* edit, `status` untouched.
//
// Two deliberate divergences, each with its reason at the point it happens:
//
//   1. The size gate is 50 MB, the bucket's real limit, not the modal's 200 MB
//      constant — see InfluencerMediaService.
//   2. Uploads go to `{uid}/videos/…`, because the live storage policy requires the
//      uid to be the first folder — also InfluencerMediaService.
//
// A third divergence, "no publish to social step", no longer holds: on a
// brand-new video's successful create, `PublishToSocialButton`'s trigger point
// (`InfluencerVideoModal.tsx:232-239`, `contentType: "reel"`, the thumbnail as
// the sole media URL) is now reproduced via `showPublishEverywhereDialog`
// before the form pops — followed by `RunAdButton`'s trigger point
// (`InfluencerVideoModal.tsx:240-246`, same content/media), reproduced via
// `offerBoostDialog`.
//
// Built from `portal_kit.dart` like the two existing wizards, so it reads as part
// of the same family rather than as a new dialect.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/influencer_video_options.dart';
import '../../models/influencer_video_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/influencer_media_service.dart';
import '../../services/influencer_video_service.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../post_property/portal_icon.dart';
import '../post_property/portal_kit.dart';
import '../post_property/portal_theme.dart';
import '../social/create_campaign_dialog.dart';
import '../social/publish_everywhere_dialog.dart';

/// Result handed back to whoever pushed the form, so a list can refresh without
/// re-querying on every pop.
enum InfluencerVideoFormResult { created, updated }

/// Matches [showPublishEverywhereDialog]'s signature, so a test can swap in a
/// no-op stub instead of the real dialog — which would otherwise open against
/// a live `SocialService` and hang the test waiting for a tap that never
/// comes, exactly like [videoService]/[mediaService]/[picker] below.
typedef PublishDialogLauncher =
    Future<void> Function(
      BuildContext context, {
      required String userId,
      required String contentType,
      required String contentId,
      required List<String> mediaUrls,
      String? title,
    });

class InfluencerVideoFormScreen extends StatefulWidget {
  const InfluencerVideoFormScreen({
    super.key,
    this.editing,
    this.videoService,
    this.mediaService,
    this.picker,
    this.publishDialogLauncher,
    this.boostDialogLauncher,
  });

  /// The video being edited, or null when creating.
  ///
  /// The portal seeds its form from `editingVideo` the same way
  /// (InfluencerVideoModal.tsx:29-38), including keeping the existing media URLs as
  /// the previews so an edit that changes only the title re-uploads nothing.
  final InfluencerVideoModel? editing;

  @visibleForTesting
  final InfluencerVideoService? videoService;

  @visibleForTesting
  final InfluencerMediaService? mediaService;

  @visibleForTesting
  final ImagePicker? picker;

  @visibleForTesting
  final PublishDialogLauncher? publishDialogLauncher;

  @visibleForTesting
  final PublishDialogLauncher? boostDialogLauncher;

  @override
  State<InfluencerVideoFormScreen> createState() =>
      _InfluencerVideoFormScreenState();
}

class _InfluencerVideoFormScreenState extends State<InfluencerVideoFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _hashtags;

  // ── Property Listing Video fields ──────────────────────────────────────
  late final TextEditingController _propertyLocation;
  late final TextEditingController _propertyPrice;
  late final TextEditingController _propertyArea;
  late final TextEditingController _propertyBedrooms;
  late final TextEditingController _propertyBathrooms;
  String? _propertyListingType;
  String? _propertyCategory;

  late final InfluencerVideoService _service =
      widget.videoService ?? InfluencerVideoService();
  late final InfluencerMediaService _media =
      widget.mediaService ?? InfluencerMediaService();
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  late final PublishDialogLauncher _publishDialogLauncher =
      widget.publishDialogLauncher ?? showPublishEverywhereDialog;
  late final PublishDialogLauncher _boostDialogLauncher =
      widget.boostDialogLauncher ?? offerBoostDialog;

  String? _videoType;

  /// A newly picked file, or null when the stored URL still stands.
  ///
  /// Kept as the `XFile` `image_picker` returns, not converted to a
  /// `dart:io.File` — on Flutter Web an `XFile`'s "path" is a `blob:` URL,
  /// and `dart:io.File` operations (`exists`/`length`/`readAsBytes`) throw
  /// `Unsupported operation` there. `XFile.readAsBytes()` works on every
  /// platform, which is all [InfluencerMediaService] actually needs.
  XFile? _videoFile;
  XFile? _thumbnailFile;

  /// What the preview shows: a stored URL on an edit, a local path once picked.
  String _videoPreview = '';
  String _thumbnailPreview = '';

  bool _submitting = false;

  /// Shown under the submit button while an upload runs, so a 40 MB video does
  /// not look like a hang.
  String? _stage;

  /// Populated on a failed submit, rendered by [PortalValidationSummary] — the
  /// modal raises one toast per problem; a summary says all of them at once.
  List<String> _issues = const [];

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _title = TextEditingController(text: editing?.title ?? '');
    _description = TextEditingController(text: editing?.description ?? '');
    _hashtags = TextEditingController(
      text: joinInfluencerHashtags(editing?.hashtags ?? const []),
    );
    _videoType = editing?.videoType;
    _videoPreview = editing?.videoUrl ?? '';
    _thumbnailPreview = editing?.thumbnailUrl ?? '';

    _propertyLocation = TextEditingController(
      text: editing?.propertyLocation ?? '',
    );
    _propertyPrice = TextEditingController(text: editing?.propertyPrice ?? '');
    _propertyArea = TextEditingController(text: editing?.propertyArea ?? '');
    _propertyBedrooms = TextEditingController(
      text: editing?.propertyBedrooms?.toString() ?? '',
    );
    _propertyBathrooms = TextEditingController(
      text: editing?.propertyBathrooms?.toString() ?? '',
    );
    _propertyListingType = editing?.propertyListingType;
    _propertyCategory = editing?.propertyCategory;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hashtags.dispose();
    _propertyLocation.dispose();
    _propertyPrice.dispose();
    _propertyArea.dispose();
    _propertyBedrooms.dispose();
    _propertyBathrooms.dispose();
    super.dispose();
  }

  bool get _isPropertyListing => _videoType == 'property_listing';

  // ── Picking ─────────────────────────────────────────────────────────────

  Future<void> _pickVideo() async {
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _videoFile = picked;
      _videoPreview = picked.path;
      // Picking a video answers the "upload a video" issue; leaving it listed
      // would be stale.
      _issues = const [];
    });
  }

  Future<void> _pickThumbnail() async {
    // The portal runs compressImage(file, {maxDimension: 1280, quality: 0.8})
    // after selection; image_picker does it during selection, which is how
    // ProfileMediaService handles the same step.
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _thumbnailFile = picked;
      _thumbnailPreview = picked.path;
    });
  }

  void _clearThumbnail() {
    setState(() {
      _thumbnailFile = null;
      _thumbnailPreview = '';
    });
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  /// The modal's two pre-flight checks (:112-118), plus — when
  /// [_isPropertyListing] — the same property-field rules
  /// `influencer-video-save`'s `validateCommon` enforces, so a bad property
  /// value is caught here instead of after an upload finishes.
  List<String> _validate() {
    final issues = <String>[];
    if (!_isEditing && _videoFile == null) {
      issues.add('Please upload a video file.');
    }
    if (_title.text.trim().isEmpty) {
      issues.add('A title is required.');
    }
    if (!isValidInfluencerVideoType(_videoType)) {
      issues.add('Choose a video type.');
    }

    if (_isPropertyListing) {
      if (_propertyLocation.text.trim().isEmpty) {
        issues.add('Property location is required.');
      }
      final price = _propertyPrice.text.trim();
      if (price.isEmpty) {
        issues.add('Property price is required.');
      } else if (!kPropertyPricePattern.hasMatch(price)) {
        issues.add('Property price must be a whole number of rupees.');
      }
      if (!kPropertyListingTypes.contains(_propertyListingType)) {
        issues.add('Listing type must be sale, rent, or lease.');
      }
      if (!kPropertyListingCategories.contains(_propertyCategory)) {
        issues.add(
          'Property type must be Residential, Commercial, PG/Co-living, '
          'Land, or Others.',
        );
      }
      final area = _propertyArea.text.trim();
      if (area.isNotEmpty && !kPropertyAreaPattern.hasMatch(area)) {
        issues.add('Property area must be a valid number (sq.ft).');
      }
      for (final (label, text) in [
        ('Bedrooms', _propertyBedrooms.text.trim()),
        ('Bathrooms', _propertyBathrooms.text.trim()),
      ]) {
        if (text.isEmpty) continue;
        final n = int.tryParse(text);
        if (n == null || n < 0 || n > kPropertyBedBathMax) {
          issues.add(
            '$label must be a whole number between 0 and $kPropertyBedBathMax.',
          );
        }
      }
    }
    return issues;
  }

  Future<void> _submit() async {
    final issues = _validate();
    if (issues.isNotEmpty) {
      setState(() => _issues = issues);
      return;
    }

    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      setState(() => _issues = const ['Sign in again to publish this video.']);
      return;
    }

    setState(() {
      _submitting = true;
      _issues = const [];
      _stage = null;
    });

    try {
      // On an edit with no new file, the stored URL is reused untouched — the
      // portal's `let videoUrl = editingVideo?.video_url` (:128-130).
      String videoUrl = widget.editing?.videoUrl ?? '';
      if (_videoFile != null) {
        videoUrl = await _media.uploadVideo(
          file: _videoFile!,
          userId: userId,
          onProgress: (stage) {
            if (mounted) setState(() => _stage = stage);
          },
        );
      }

      String? thumbnailUrl = widget.editing?.thumbnailUrl;
      if (_thumbnailFile != null) {
        if (mounted) setState(() => _stage = 'Uploading thumbnail…');
        thumbnailUrl = await _media.uploadThumbnail(
          file: _thumbnailFile!,
          userId: userId,
        );
      } else if (_thumbnailPreview.isEmpty) {
        // Cleared deliberately. Null, not '', so the column reads as absent.
        thumbnailUrl = null;
      }

      if (mounted) setState(() => _stage = 'Saving…');

      final draft = InfluencerVideoDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        videoType: _videoType!,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        hashtagsText: _hashtags.text,
        propertyLocation: _propertyLocation.text.trim(),
        propertyPrice: _propertyPrice.text.trim(),
        propertyListingType: _propertyListingType,
        propertyCategory: _propertyCategory,
        propertyBedrooms: int.tryParse(_propertyBedrooms.text.trim()),
        propertyBathrooms: int.tryParse(_propertyBathrooms.text.trim()),
        propertyArea: _propertyArea.text.trim(),
      );

      String? createdId;
      if (_isEditing) {
        await _service.update(widget.editing!.id, draft);
      } else {
        createdId = await _service.create(draft);
      }

      if (!mounted) return;
      if (createdId != null) {
        final mediaUrls = (thumbnailUrl?.isNotEmpty ?? false)
            ? [thumbnailUrl!]
            : const <String>[];
        await _publishDialogLauncher(
          context,
          userId: userId,
          contentType: 'reel',
          contentId: createdId,
          title: draft.title,
          mediaUrls: mediaUrls,
        );
        if (!mounted) return;
        await _boostDialogLauncher(
          context,
          userId: userId,
          contentType: 'reel',
          contentId: createdId,
          title: draft.title,
          mediaUrls: mediaUrls,
        );
        if (!mounted) return;
      }
      Navigator.pop(
        context,
        _isEditing
            ? InfluencerVideoFormResult.updated
            : InfluencerVideoFormResult.created,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _stage = null;
        // InfluencerMediaException and InfluencerVideoException both carry a
        // sentence meant for the user; anything else is shown as-is rather than
        // replaced with generic copy that hides the cause.
        _issues = [_message(e)];
      });
    }
  }

  static String _message(Object error) => switch (error) {
    InfluencerMediaException(:final message) => message,
    InfluencerVideoException(:final message) => message,
    _ => 'Could not save this video: $error',
  };

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isEditing ? 'Edit Video' : 'Upload Video',
          style: PortalTheme.stepHeaderTitle,
        ),
        leading: IconButton(
          icon: const PortalIcon('x', size: 20, color: PortalTheme.slate700),
          onPressed: _submitting ? null : () => Navigator.pop(context),
          tooltip: 'Close',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            PortalStepHeader(
              icon: 'video',
              title: _isEditing ? 'Edit Video' : 'Upload Video',
              subtitle: _isEditing
                  // The portal's own wording for this outcome
                  // (InfluencerVideoModal.tsx:176).
                  ? 'Saving changes sends this video back for review'
                  : 'Share a video with your audience',
            ),
            const SizedBox(height: 20),

            if (_issues.isNotEmpty) ...[
              PortalValidationSummary(messages: _issues),
              const SizedBox(height: 16),
            ],

            // ── Media ──────────────────────────────────────────────────────
            PortalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PortalSectionDivider(icon: 'video', title: 'Media'),
                  const SizedBox(height: 14),
                  PortalLabelledField(
                    label: 'Video',
                    required: true,
                    helper:
                        'Compressed to 1080p before upload. '
                        'Maximum 50 MB after compression.',
                    child: _VideoPickerTile(
                      preview: _videoPreview,
                      isLocal: _videoFile != null,
                      enabled: !_submitting,
                      onPick: _pickVideo,
                    ),
                  ),
                  const SizedBox(height: 14),
                  PortalLabelledField(
                    label: 'Thumbnail',
                    helper:
                        'Optional. A frame from the video is used if you '
                        'skip this.',
                    child: _ThumbnailPickerTile(
                      preview: _thumbnailPreview,
                      isLocal: _thumbnailFile != null,
                      enabled: !_submitting,
                      onPick: _pickThumbnail,
                      onClear: _clearThumbnail,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Type ───────────────────────────────────────────────────────
            PortalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PortalSectionDivider(icon: 'type', title: 'Video Type'),
                  const SizedBox(height: 4),
                  // A radio list, not a Select. The portal's SelectItem rows carry
                  // a title and a description each (:47-50), and a dropdown that
                  // collapses to one line would drop the descriptions.
                  for (final type in kInfluencerVideoTypes)
                    _TypeOption(
                      type: type,
                      selected: _videoType == type.id,
                      enabled: !_submitting,
                      onTap: () => setState(() {
                        _videoType = type.id;
                        _issues = const [];
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Property Details ───────────────────────────────────────────
            //
            // Shown only for a Property Listing Video — mirrors
            // `influencer-video-save`'s own "only meaningful when
            // videoType === 'property_listing'" rule (see the field
            // annotations on `InfluencerVideoDraft`).
            if (_isPropertyListing) ...[
              PortalCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PortalSectionDivider(
                      icon: 'home',
                      title: 'Property Details',
                    ),
                    const SizedBox(height: 14),
                    PortalLabelledField(
                      label: 'Location',
                      required: true,
                      // The portal attaches Google Places Autocomplete
                      // straight to this plain input rather than pulling in
                      // the full map picker ("overkill for a single field
                      // here" — InfluencerVideoModal.tsx:66-68) and only
                      // ever takes the formatted address string from it, no
                      // lat/lng — same scope reproduced here with the
                      // widget the listing wizard and registration screens
                      // already use for their own address fields.
                      child: AddressAutocompleteField(
                        controller: _propertyLocation,
                        onPlaceSelected: (_, _, _) {
                          if (_issues.isNotEmpty) {
                            setState(() => _issues = const []);
                          }
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: PortalTheme.cardSurface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          hintText: 'e.g. Whitefield, Bangalore',
                          hintStyle: PortalTheme.inputText.copyWith(
                            color: PortalTheme.radioIdle,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: _issues.any((i) => i.contains('location'))
                                  ? PortalTheme.fieldError
                                  : PortalTheme.cardBorder,
                              width: _issues.any(
                                    (i) => i.contains('location'),
                                  )
                                  ? 1.5
                                  : 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: _issues.any((i) => i.contains('location'))
                                  ? PortalTheme.fieldError
                                  : PortalTheme.cardBorder,
                              width: _issues.any(
                                    (i) => i.contains('location'),
                                  )
                                  ? 1.5
                                  : 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: PortalTheme.accent,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PortalLabelledField(
                      label: 'Price',
                      required: true,
                      child: PortalTextField(
                        controller: _propertyPrice,
                        hint: 'Whole rupees, e.g. 8500000',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        prefix: PortalIconTint(
                          'indian-rupee',
                          color: PortalTheme.radioIdle,
                        ),
                        hasError: _issues.any((i) => i.contains('price')),
                        onChanged: (_) {
                          if (_issues.isNotEmpty) {
                            setState(() => _issues = const []);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    PortalLabelledField(
                      label: 'Listing Type',
                      required: true,
                      child: PortalSelect(
                        value: _propertyListingType,
                        placeholder: 'Select listing type',
                        options: kPropertyListingTypes,
                        labelFor: propertyListingTypeLabel,
                        hasError: _issues.any(
                          (i) => i.contains('Listing type'),
                        ),
                        onChanged: (v) => setState(() {
                          _propertyListingType = v;
                          _issues = const [];
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PortalLabelledField(
                      label: 'Property Type',
                      required: true,
                      child: PortalSelect(
                        value: _propertyCategory,
                        placeholder: 'Select property type',
                        options: kPropertyListingCategories,
                        labelFor: propertyListingCategoryLabel,
                        hasError: _issues.any(
                          (i) => i.contains('Property type'),
                        ),
                        onChanged: (v) => setState(() {
                          _propertyCategory = v;
                          _issues = const [];
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PortalLabelledField(
                      label: 'Area',
                      helper: 'Optional, in sq.ft.',
                      child: PortalTextField(
                        controller: _propertyArea,
                        hint: 'e.g. 1200',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        hasError: _issues.any((i) => i.contains('area')),
                      ),
                    ),
                    if (propertyCategoryHasBedBath(_propertyCategory)) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PortalLabelledField(
                              label: 'Bedrooms',
                              helper: 'Optional',
                              child: PortalTextField(
                                controller: _propertyBedrooms,
                                hint: '0–20',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PortalLabelledField(
                              label: 'Bathrooms',
                              helper: 'Optional',
                              child: PortalTextField(
                                controller: _propertyBathrooms,
                                hint: '0–20',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Details ────────────────────────────────────────────────────
            PortalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PortalSectionDivider(
                    icon: 'file-text',
                    title: 'Details',
                  ),
                  const SizedBox(height: 14),
                  PortalLabelledField(
                    label: 'Title',
                    required: true,
                    child: PortalTextField(
                      controller: _title,
                      hint: 'Give your video a title',
                      hasError: _issues.any((i) => i.contains('title')),
                      onChanged: (_) {
                        if (_issues.isNotEmpty)
                          setState(() => _issues = const []);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  PortalLabelledField(
                    label: 'Description',
                    child: PortalTextField(
                      controller: _description,
                      hint: 'What is this video about?',
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  PortalLabelledField(
                    label: 'Hashtags',
                    helper: 'Comma separated. The leading # is optional.',
                    child: PortalTextField(
                      controller: _hashtags,
                      hint: 'pune, 3bhk, newlaunch',
                      prefix: PortalIcon(
                        'hash',
                        size: 14,
                        color: PortalTheme.radioIdle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _SubmitBar(
              label: _isEditing ? 'Save Changes' : 'Upload Video',
              submitting: _submitting,
              stage: _stage,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Media tiles ─────────────────────────────────────────────────────────────

/// The video slot: empty prompt, or the chosen file with an inline preview
/// player and a swap action.
///
/// Mirrors `InfluencerVideoModal.tsx`'s inline `<video controls>` preview
/// (`:329-346`) — shown immediately once a file is picked, before upload,
/// using the same `video_player` package/lifecycle the reels feed already
/// uses (`ReelVideoView`/`ReelControllerManager`), just a single local
/// controller instead of that sliding window.
class _VideoPickerTile extends StatefulWidget {
  const _VideoPickerTile({
    required this.preview,
    required this.isLocal,
    required this.enabled,
    required this.onPick,
  });

  final String preview;
  final bool isLocal;
  final bool enabled;
  final VoidCallback onPick;

  @override
  State<_VideoPickerTile> createState() => _VideoPickerTileState();
}

class _VideoPickerTileState extends State<_VideoPickerTile> {
  VideoPlayerController? _controller;
  String? _controllerSource;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(_VideoPickerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      // Submission is starting (`enabled: !_submitting` in the parent).
      // Tear the live platform view down now, before `_submit()`'s
      // publish/boost dialogs and final `Navigator.pop` run — a
      // `VideoPlayer` still mounted through that route churn is a known
      // trigger for Flutter's "check that it really is our descendant"
      // `InheritedElement` assertion (platform views don't survive
      // Navigator transitions cleanly).
      _controller?.dispose();
      _controller = null;
      _controllerSource = null;
      _initFailed = false;
      return;
    }
    if (widget.enabled &&
        (oldWidget.preview != widget.preview ||
            oldWidget.isLocal != widget.isLocal ||
            !oldWidget.enabled)) {
      _syncController();
    }
  }

  bool _initFailed = false;

  void _syncController() {
    final preview = widget.preview;
    final previous = _controller;
    if (preview.isEmpty) {
      _controller = null;
      _controllerSource = null;
      _initFailed = false;
      previous?.dispose();
      return;
    }
    if (preview == _controllerSource) return;

    _controllerSource = preview;
    _initFailed = false;

    VideoPlayerController controller;
    try {
      // `VideoPlayerController.file` needs `dart:io` file access, which is
      // unsupported on Flutter Web (throws "Unsupported operation:
      // Platform._operatingSystem"). A local pick's path on web is already a
      // `blob:` URL the browser can play directly, so it goes through the
      // network-url controller instead — same as a stored remote video.
      controller = (widget.isLocal && !kIsWeb)
          ? VideoPlayerController.file(File(preview))
          : VideoPlayerController.networkUrl(Uri.parse(preview));
    } catch (e) {
      _controller = null;
      _initFailed = true;
      previous?.dispose();
      return;
    }

    _controller = controller;
    controller
      ..setLooping(true)
      ..initialize()
          .then((_) {
            if (mounted && _controller == controller) setState(() {});
          })
          .catchError((_) {
            if (mounted && _controller == controller) {
              setState(() => _initFailed = true);
            }
          });
    previous?.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final chosen = preview.isNotEmpty;

    if (!chosen) {
      return InkWell(
        onTap: widget.enabled ? widget.onPick : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PortalTheme.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PortalTheme.cardBorder),
          ),
          child: Row(
            children: [
              PortalIcon('upload', size: 20, color: PortalTheme.radioIdle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose a video', style: PortalTheme.inputText),
                    const SizedBox(height: 2),
                    Text('MP4, MOV or WEBM', style: PortalTheme.helperText),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              onTap: ready ? _togglePlay : null,
              child: ColoredBox(
                color: Colors.black,
                child: ready
                    ? Stack(
                        alignment: Alignment.center,
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: controller.value.size.width,
                              height: controller.value.size.height,
                              child: VideoPlayer(controller),
                            ),
                          ),
                          if (!controller.value.isPlaying)
                            const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                        ],
                      )
                    : !widget.enabled
                    ? const Center(
                        child: Icon(
                          Icons.videocam_outlined,
                          color: Colors.white54,
                          size: 32,
                        ),
                      )
                    : _initFailed
                    ? const Center(
                        child: Icon(
                          Icons.videocam_off_outlined,
                          color: Colors.white70,
                          size: 32,
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: widget.enabled ? widget.onPick : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PortalTheme.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PortalTheme.accent),
            ),
            child: Row(
              children: [
                PortalIcon('play', size: 20, color: PortalTheme.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileLabel(preview),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PortalTheme.inputText,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isLocal ? 'Ready to upload' : 'Current video',
                        style: PortalTheme.helperText,
                      ),
                    ],
                  ),
                ),
                Text(
                  'Change',
                  style: PortalTheme.helperText.copyWith(
                    color: PortalTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Last path segment, or a short label when the preview is a remote URL whose
  /// generated name would say nothing useful.
  static String _fileLabel(String preview) {
    if (preview.startsWith('http')) return 'Uploaded video';
    final separator = preview.lastIndexOf(RegExp(r'[/\\]'));
    return separator < 0 ? preview : preview.substring(separator + 1);
  }
}

/// The thumbnail slot: a 16:9 preview with a clear button, or an empty prompt.
class _ThumbnailPickerTile extends StatelessWidget {
  const _ThumbnailPickerTile({
    required this.preview,
    required this.isLocal,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String preview;
  final bool isLocal;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (preview.isEmpty) {
      return InkWell(
        onTap: enabled ? onPick : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PortalTheme.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PortalTheme.cardBorder),
          ),
          child: Row(
            children: [
              PortalIcon('image-plus', size: 20, color: PortalTheme.radioIdle),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Choose a thumbnail', style: PortalTheme.inputText),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            // `Image.file` needs `dart:io` file access, unsupported on
            // Flutter Web. A local pick's path on web is already a `blob:`
            // URL the browser can load directly, so it goes through
            // `Image.network` instead — same fix as the video preview tile
            // above.
            child: (isLocal && !kIsWeb)
                ? Image.file(File(preview), fit: BoxFit.cover)
                : Image.network(
                    preview,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: const Color(0xFFEEECF8),
                      child: Center(
                        child: PortalIcon(
                          'image',
                          size: 32,
                          color: PortalTheme.radioIdle,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        // A Wrap: two TextButtons at 130% text exceed the 262 dp card column, and
        // stacking them reads better than shrinking the tap targets.
        Wrap(
          children: [
            TextButton(
              onPressed: enabled ? onPick : null,
              child: const Text('Replace'),
            ),
            TextButton(
              onPressed: enabled ? onClear : null,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Type option ─────────────────────────────────────────────────────────────

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.type,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final InfluencerVideoType type;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? PortalTheme.accent : PortalTheme.radioIdle,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.title, style: PortalTheme.inputText),
                  const SizedBox(height: 2),
                  Text(type.description, style: PortalTheme.helperText),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Submit ──────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.label,
    required this.submitting,
    required this.stage,
    required this.onSubmit,
  });

  final String label;
  final bool submitting;
  final String? stage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: PortalTheme.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: PortalTheme.accent.withValues(
                alpha: 0.5,
              ),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(label, style: PortalTheme.navButton),
          ),
        ),
        if (stage != null) ...[
          const SizedBox(height: 8),
          Text(stage!, style: PortalTheme.helperText),
        ],
      ],
    );
  }
}
