import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../providers/post_property_provider.dart';
import '../listing_constants.dart';
import '../portal_kit.dart' show PortalSelect;

/// Step 8: local media selection (no upload — files stay on-device until a
/// backend integration phase), contact details and hashtags. Mirrors the
/// React MediaAndFinalStep's fields, minus the actual upload/submission.
class MediaContactStep extends StatefulWidget {
  const MediaContactStep({super.key});

  @override
  State<MediaContactStep> createState() => _MediaContactStepState();
}

/// Every half-hour across a full day, formatted "H:MM AM/PM" — the exact
/// shape `ListingPattern.timeRange` (listing_validators.dart) expects on
/// each side of a range. Picking two of these and joining them with " - "
/// can never produce anything but a valid time range, which is the actual
/// fix for "6 am to 10 pm" being rejected: a free-text field can be typed
/// in a format the validator doesn't recognise, a dropdown built from this
/// list cannot.
final List<String> _kTimeOfDayOptions = List.unmodifiable(() {
  final options = <String>[];
  for (var minutes = 0; minutes < 24 * 60; minutes += 30) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour24 < 12 ? 'AM' : 'PM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    options.add('$hour12:${minute.toString().padLeft(2, '0')} $period');
  }
  return options;
}());

/// Splits a saved "Best Time to Call" value — old free-typed text or this
/// dropdown's own "$from - $to" — into its two halves, each matched back
/// onto [_kTimeOfDayOptions] so an existing value still pre-selects both
/// dropdowns instead of showing blank. Returns nulls where a half can't be
/// matched (an old value in some other shape entirely) rather than
/// guessing.
(String?, String?) _splitBestTimeToCall(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return (null, null);

  final parts = trimmed.split(RegExp(r'-|\bto\b', caseSensitive: false));
  if (parts.length != 2) return (null, null);
  return (_matchTimeOption(parts[0]), _matchTimeOption(parts[1]));
}

String? _matchTimeOption(String raw) {
  final cleaned = raw.trim().toUpperCase();
  for (final option in _kTimeOfDayOptions) {
    if (option.toUpperCase() == cleaned) return option;
  }
  // Tolerates a legacy value with no minutes, e.g. "10 AM" -> "10:00 AM".
  final noMinutes = RegExp(r'^(\d{1,2})\s*(AM|PM)$').firstMatch(cleaned);
  if (noMinutes == null) return null;
  final normalized = '${noMinutes.group(1)}:00 ${noMinutes.group(2)}';
  for (final option in _kTimeOfDayOptions) {
    if (option.toUpperCase() == normalized) return option;
  }
  return null;
}

class _MediaContactStepState extends State<MediaContactStep> {
  /// Photo categories for the current listing, straight from the T0
  /// constants. React swaps the whole set for land — Sajra / Land video /
  /// Land images / Others (MediaAndFinalStep.tsx:32).
  List<ListingOption> _categoriesFor(PropertyCategory? category) =>
      category == PropertyCategory.land
      ? kLandImageCategories
      : kDefaultImageCategories;

  final ImagePicker _picker = ImagePicker();
  String? _selectedCategoryId;

  /// Default category for newly added photos: the first of the active set,
  /// reset automatically when the category swap changes that set.
  String _activeCategory(List<ListingOption> options) {
    final id = _selectedCategoryId;
    if (id != null && options.any((o) => o.id == id)) return id;
    return options.first.id;
  }

  late final TextEditingController _contactNameController;
  late final TextEditingController _contactPhoneController;
  late final TextEditingController _contactEmailController;
  late final TextEditingController _whatsappController;
  String? _bestTimeFrom;
  String? _bestTimeTo;
  late final TextEditingController _hashtagsController;
  late final TextEditingController _ownerManagerNameController;
  late final TextEditingController _alternateNumberController;

  @override
  void initState() {
    super.initState();
    final p = context.read<PostPropertyProvider>();
    _contactNameController = TextEditingController(text: p.contactName);
    _contactPhoneController = TextEditingController(text: p.contactPhone);
    _contactEmailController = TextEditingController(text: p.contactEmail);
    _whatsappController = TextEditingController(text: p.whatsappNumber);
    final bestTime = _splitBestTimeToCall(p.bestTimeToCall);
    _bestTimeFrom = bestTime.$1;
    _bestTimeTo = bestTime.$2;
    _hashtagsController = TextEditingController(text: p.hashtags);
    _ownerManagerNameController = TextEditingController(
      text: p.text('ownerManagerName'),
    );
    _alternateNumberController = TextEditingController(
      text: p.text('alternateNumber'),
    );
    // TEMPORARY — P0 real-device edit-hydration trace.
    debugPrint(
      '[EDIT_TRACE][MEDIA] provider.contactPhone="${p.contactPhone}" '
      'controller.contactPhone="${_contactPhoneController.text}"',
    );
    debugPrint(
      '[EDIT_TRACE][MEDIA] provider.contactEmail="${p.contactEmail}" '
      'controller.contactEmail="${_contactEmailController.text}"',
    );
    debugPrint(
      '[EDIT_TRACE][MEDIA] provider.hashtags="${p.hashtags}" '
      'controller.hashtags="${_hashtagsController.text}"',
    );
  }

  /// Writes the combined "$from - $to" to the provider only once both
  /// halves are picked — a single half saved alone ("6:00 AM -") would fail
  /// [ListingPattern.timeRange], so this leaves the field genuinely blank
  /// (a no-op, since it's optional) until the range is actually complete.
  void _syncBestTimeToCall() {
    final from = _bestTimeFrom;
    final to = _bestTimeTo;
    context.read<PostPropertyProvider>().setBestTimeToCall(
      from != null && to != null ? '$from - $to' : '',
    );
  }

  @override
  void dispose() {
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _whatsappController.dispose();
    _hashtagsController.dispose();
    _ownerManagerNameController.dispose();
    _alternateNumberController.dispose();
    super.dispose();
  }

  // React runs compressMedia() before upload; that implementation is
  // browser-only (canvas re-encoding + WebCodecs) and cannot be ported. The
  // equivalent on mobile is to let image_picker downscale and re-encode at
  // pick time, which keeps uploads to a sane size instead of sending a
  // full-resolution phone photo — Flutter previously applied no compression
  // at all.
  static const int _maxImageDimension = 1920;
  static const int _imageQuality = 82;
  // Portal's own hard ceiling (MediaAndFinalStep.tsx:74-77) — a rejected file
  // just isn't added, same as the portal's alert-and-skip behavior.
  static const int _maxFileBytes = 10 * 1024 * 1024;

  // Flutter-only caps (no portal precedent) requested to keep listings from
  // shipping with an unbounded number of photos/videos.
  static const int _maxPhotos = 10;
  static const int _maxVideos = 5;

  bool _isVideoCategory(String category) =>
      category == 'property_video' || category == 'land_video';

  int _photoCount(PostPropertyProvider provider) =>
      provider.mediaItems.where((m) => !_isVideoCategory(m.category)).length;

  int _videoCount(PostPropertyProvider provider) =>
      provider.mediaItems.where((m) => _isVideoCategory(m.category)).length;

  void _showLimitSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// True once any file over the portal's 10MB ceiling was rejected —
  /// surfaced as a snackbar, the mobile equivalent of the portal's `alert()`.
  Future<bool> _tooLarge(XFile file) async {
    if (await file.length() <= _maxFileBytes) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} is over 10MB and was skipped.')),
      );
    }
    return true;
  }

  Future<void> _pickFromGallery() async {
    final images = await _picker.pickMultiImage(
      maxWidth: _maxImageDimension.toDouble(),
      maxHeight: _maxImageDimension.toDouble(),
      imageQuality: _imageQuality,
    );
    if (!mounted || images.isEmpty) return;
    final provider = context.read<PostPropertyProvider>();
    final category = _activeCategory(_categoriesFor(provider.category));
    var photoCount = _photoCount(provider);
    var limitHit = false;
    for (final image in images) {
      if (photoCount >= _maxPhotos) {
        limitHit = true;
        break;
      }
      if (await _tooLarge(image)) continue;
      provider.addMediaItem(image, category);
      photoCount++;
    }
    if (limitHit) {
      _showLimitSnackBar('You can upload up to $_maxPhotos photos.');
    }
  }

  Future<void> _pickFromCamera() async {
    final provider = context.read<PostPropertyProvider>();
    if (_photoCount(provider) >= _maxPhotos) {
      _showLimitSnackBar('You can upload up to $_maxPhotos photos.');
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxImageDimension.toDouble(),
      maxHeight: _maxImageDimension.toDouble(),
      imageQuality: _imageQuality,
    );
    if (!mounted || image == null) return;
    if (await _tooLarge(image)) return;
    provider.addMediaItem(
      image,
      _activeCategory(_categoriesFor(provider.category)),
    );
  }

  /// The portal accepts `video/*` alongside images on the same picker
  /// (MediaAndFinalStep.tsx:222) — Flutter only ever exposed a "Property
  /// Video"/"Land video" category a user could tag a *photo* with, with no
  /// way to actually attach a video file.
  Future<void> _pickVideo() async {
    final provider = context.read<PostPropertyProvider>();
    if (_videoCount(provider) >= _maxVideos) {
      _showLimitSnackBar('You can upload up to $_maxVideos videos.');
      return;
    }
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || video == null) return;
    if (await _tooLarge(video)) return;
    final categories = _categoriesFor(provider.category);
    final videoCategory = categories.any((c) => c.id == 'property_video')
        ? 'property_video'
        : categories.any((c) => c.id == 'land_video')
        ? 'land_video'
        : _activeCategory(categories);
    provider.addMediaItem(video, videoCategory);
  }

  String _categoryLabel(List<ListingOption> options, String id) {
    for (final o in options) {
      if (o.id == id) return o.label;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    final isPg = provider.category == PropertyCategory.pg;
    final categories = _categoriesFor(provider.category);
    final activeCategory = _activeCategory(categories);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardCard(
          icon: Icons.photo_library_outlined,
          title: 'Property Images *',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add at least one image. No upload happens yet — images stay on this device.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              WizardField(
                label: 'Category for new photos',
                child: WizardChipGroup(
                  options: categories.map((c) => c.label).toList(),
                  selected: _categoryLabel(categories, activeCategory),
                  onSelected: (label) {
                    setState(() {
                      _selectedCategoryId = categories
                          .firstWhere((c) => c.label == label)
                          .id;
                    });
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromCamera,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Video'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Photos already on the listing. Without this, editing a
              // listing showed an empty picker even though it had images, the
              // user could not remove or re-tag any of them, and there was no
              // way to choose which one is the main display image.
              if (provider.existingMedia.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Current photos',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: provider.existingMedia.length,
                  itemBuilder: (context, index) {
                    final media = provider.existingMedia[index];
                    final isMain =
                        provider.mainDisplayMediaUrl == media.url ||
                        (provider.mainDisplayMediaUrl.isEmpty &&
                            index == 0 &&
                            provider.existingMedia.isNotEmpty);
                    return Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _isVideoCategory(media.category)
                                    ? _VideoPreviewTile(
                                        source: media.url,
                                        isNetwork: true,
                                      )
                                    : Image.network(
                                        media.url,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                  ),
                                                ),
                                      ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => context
                                      .read<PostPropertyProvider>()
                                      .removeExistingMedia(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                left: 4,
                                child: GestureDetector(
                                  onTap: () => context
                                      .read<PostPropertyProvider>()
                                      .setMainDisplayMediaUrl(
                                        isMain ? '' : media.url,
                                      ),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isMain ? Icons.star : Icons.star_border,
                                      color: isMain
                                          ? Colors.amber
                                          : Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => context
                              .read<PostPropertyProvider>()
                              .setExistingMediaCategory(index, activeCategory),
                          child: Text(
                            _categoryLabel(categories, media.category),
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10,
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              if (provider.mediaItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: provider.mediaItems.length,
                  itemBuilder: (context, index) {
                    final item = provider.mediaItems[index];
                    return Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _isVideoCategory(item.category)
                                    ? _VideoPreviewTile(
                                        source: item.file.path,
                                        isNetwork: kIsWeb,
                                      )
                                    // `Image.file` needs `dart:io` file
                                    // access, unsupported on Flutter Web —
                                    // an `XFile`'s path on web is already a
                                    // `blob:` URL the browser can load
                                    // directly, so it goes through
                                    // `Image.network` there instead.
                                    : kIsWeb
                                    ? Image.network(
                                        item.file.path,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                  ),
                                                ),
                                      )
                                    : Image.file(
                                        File(item.file.path),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                  ),
                                                ),
                                      ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => context
                                      .read<PostPropertyProvider>()
                                      .removeMediaItem(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _categoryLabel(categories, item.category),
                          style: AppTextStyles.caption.copyWith(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.contact_phone_outlined,
          title: 'Contact Information',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPg) ...[
                WizardField(
                  label: 'PG Owner / Manager Name',
                  child: WizardTextField(
                    controller: _ownerManagerNameController,
                    hint: 'e.g., Rahul Sharma',
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('ownerManagerName', v),
                  ),
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Alternate Contact Number',
                  child: WizardTextField(
                    controller: _alternateNumberController,
                    hint: '+91 98765 00000',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('alternateNumber', v),
                  ),
                ),
                const WizardDivider(),
              ],
              WizardField(
                label: 'Contact Name *',
                child: WizardTextField(
                  controller: _contactNameController,
                  hint: 'Your full name',
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                  ],
                  onChanged: (v) =>
                      context.read<PostPropertyProvider>().setContactName(v),
                ),
              ),
              const WizardDivider(),
              Row(
                children: [
                  Expanded(
                    child: WizardField(
                      label: 'Phone Number *',
                      child: WizardTextField(
                        controller: _contactPhoneController,
                        hint: '+91 98765 43210',
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setContactPhone(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Email Address',
                      child: WizardTextField(
                        controller: _contactEmailController,
                        hint: 'your.email@example.com',
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setContactEmail(v),
                      ),
                    ),
                  ),
                ],
              ),
              const WizardDivider(),
              Row(
                children: [
                  Expanded(
                    child: WizardField(
                      label: 'WhatsApp Number *',
                      child: WizardTextField(
                        controller: _whatsappController,
                        hint: '+91 98765 43210',
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setWhatsappNumber(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Best Time to Call *',
                      child: Row(
                        children: [
                          Expanded(
                            child: PortalSelect(
                              value: _bestTimeFrom,
                              placeholder: 'From',
                              options: _kTimeOfDayOptions,
                              onChanged: (v) => setState(() {
                                _bestTimeFrom = v;
                                _syncBestTimeToCall();
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PortalSelect(
                              value: _bestTimeTo,
                              placeholder: 'To',
                              options: _kTimeOfDayOptions,
                              onChanged: (v) => setState(() {
                                _bestTimeTo = v;
                                _syncBestTimeToCall();
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.tag_outlined,
          title: 'Hashtags',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WizardTextField(
                controller: _hashtagsController,
                hint: '#modern #furnished #parking',
                onChanged: (v) =>
                    context.read<PostPropertyProvider>().setHashtags(v),
              ),
              const SizedBox(height: 8),
              Text(
                'Use hashtags to help property seekers find your property.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Real inline preview for a video attached to the listing — local file,
/// already-uploaded URL, or a web `blob:`/network source — so the uploader
/// can confirm the right clip was picked before submitting. Previously this
/// tile was a static grey box with a generic play icon (new videos), or an
/// `Image.network` call that silently failed into a broken-image icon
/// (existing videos in edit mode) — neither ever showed the actual content.
///
/// Shows the first frame once the controller initialises; tapping toggles
/// play/pause in place. Never blocks the picker or submission on a preview
/// that fails to load — it just falls back to a "can't preview" icon.
class _VideoPreviewTile extends StatefulWidget {
  final String source;
  final bool isNetwork;

  const _VideoPreviewTile({required this.source, required this.isNetwork});

  @override
  State<_VideoPreviewTile> createState() => _VideoPreviewTileState();
}

class _VideoPreviewTileState extends State<_VideoPreviewTile> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    final controller = widget.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.source))
        : VideoPlayerController.file(File(widget.source));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: Colors.grey.shade800,
        child: const Icon(Icons.videocam_off, color: Colors.white, size: 28),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.grey.shade800,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        color: Colors.grey.shade800,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
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
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
