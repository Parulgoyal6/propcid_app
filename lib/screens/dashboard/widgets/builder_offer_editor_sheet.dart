// screens/dashboard/widgets/builder_offer_editor_sheet.dart
//
// Create or edit a marketed offer — the port of `MarketToBrokersModal.tsx`.
//
// WHY THIS IS HERE AND NOT ON THE BROKER DASHBOARD
// -----------------------------------------------
// The contract files "Market-to-Brokers" under Spec I, alongside three broker
// surfaces, and guesses its table as `builder_networks`/`network_leads`. Both are
// wrong, and the code settles it: `MarketToBrokersModal.tsx:152-176` writes
// **`builder_project_offers`** — insert with `builder_id: user.id`, update by offer
// id — and its only two mount points are `BuilderProjectsManager.tsx:835` and
// `FilteredOffersList.tsx:131`, both builder screens. It touches neither network
// table.
//
// `builder_project_offers`' RLS is `USING/WITH CHECK (auth.uid() = builder_id)`, so
// a broker-dashboard form against it would have every write refused. Despite the
// name and the `features/network/` path, this is the builder's offer editor.
//
// So it lands in the Builder Marketed Offers section, which closes the two gaps
// Spec H reported: H-1 (no offer edit) and H-2 (no offer create).
//
// MEDIA REUSES ProjectMediaService
// --------------------------------
// The portal uploads to the `project-media` bucket (`:80-126`), which
// `ProjectMediaService` already owns — same bucket, same 50 MB ceiling, same path
// prefixes. It is used as-is rather than reimplemented.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../services/project_media_service.dart';
import 'builder_section_kit.dart';

/// What the sheet hands back.
class BuilderOfferDraft {
  const BuilderOfferDraft({
    required this.title,
    required this.description,
    required this.mediaUrls,
    this.videoUrl,
  });

  final String title;
  final String description;
  final List<String> mediaUrls;
  final String? videoUrl;

  /// The columns the portal writes.
  ///
  /// `:153-159` (update) and `:167-175` (insert). `status` is `'active'` on insert
  /// only — the update path never touches it, so an offer a builder later
  /// deactivated is not silently reactivated by an edit.
  Map<String, dynamic> toPayload({required bool isCreate}) => {
    'offer_title': title,
    'offer_description': description,
    'offer_media_urls': mediaUrls,
    'offer_video_url': videoUrl,
    if (isCreate) 'status': 'active',
  };
}

/// Title, description, images and an optional video.
///
/// The portal additionally lets a builder pick from the project's **existing**
/// images (`:204`, `uniqueImages`) as well as upload new ones. Both are offered
/// here: [project] supplies the existing set.
class BuilderOfferEditorSheet extends StatefulWidget {
  const BuilderOfferEditorSheet({
    super.key,
    required this.project,
    this.editing,
    this.mediaService,
    this.picker,
  });

  /// The project the offer is for. Its images seed the picker.
  final ProjectModel project;

  /// Null when creating.
  final BuilderOffer? editing;

  @visibleForTesting
  final ProjectMediaService? mediaService;

  @visibleForTesting
  final ImagePicker? picker;

  @override
  State<BuilderOfferEditorSheet> createState() =>
      _BuilderOfferEditorSheetState();
}

class _BuilderOfferEditorSheetState extends State<BuilderOfferEditorSheet> {
  late final ProjectMediaService _media =
      widget.mediaService ?? ProjectMediaService();
  late final ImagePicker _picker = widget.picker ?? ImagePicker();

  late final _title = TextEditingController(text: widget.editing?.title ?? '');
  late final _description = TextEditingController(
    text: widget.editing?.description ?? '',
  );

  /// Every image the builder may attach — the project's own plus anything freshly
  /// uploaded, deduplicated the way the portal's `uniqueImages` is.
  late final List<String> _available = {
    ...widget.project.mediaUrls,
    ...widget.project.otherImages,
    ...?widget.editing?.mediaUrls,
  }.where((url) => url.isNotEmpty).toList();

  /// Those currently ticked.
  late final Set<String> _selected = {...?widget.editing?.mediaUrls};

  late String? _videoUrl = widget.editing?.videoUrl;

  bool _uploading = false;
  String? _error;

  bool get _isEditing => widget.editing != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // The portal compresses before upload; image_picker does it during
      // selection, the approach ProfileMediaService and the influencer form both
      // take.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final url = await _media.uploadImage(
        bytes: await File(picked.path).readAsBytes(),
        fileName: picked.path,
      );
      if (!mounted) return;
      setState(() {
        _available.add(url);
        // Newly uploaded images are ticked: a builder who just picked one meant to
        // use it.
        _selected.add(url);
        _uploading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e is ProjectMediaException
            ? e.message
            : 'That image could not be uploaded.';
      });
    }
  }

  Future<void> _addVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final url = await _media.uploadVideo(
        bytes: await File(picked.path).readAsBytes(),
        fileName: picked.path,
      );
      if (!mounted) return;
      setState(() {
        _videoUrl = url;
        _uploading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e is ProjectMediaException
            ? e.message
            : 'That video could not be uploaded.';
      });
    }
  }

  void _submit() {
    // The portal's one refusal (`:143-146`): a title is required, and the column
    // is NOT NULL.
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'A title is required.');
      return;
    }

    Navigator.pop(
      context,
      BuilderOfferDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        mediaUrls: _selected.toList(),
        videoUrl: _videoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Edit Offer' : 'Market to Brokers',
                style: AppTextStyles.heading2.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 2),
              Text(
                _isEditing
                    ? widget.project.title
                    : 'Share ${widget.project.title} with your broker network.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 18),

              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              Text(
                'Offer Title *',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 5),
              TextField(
                controller: _title,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: _decoration('e.g. Festive 5% off on all 3BHKs'),
              ),
              const SizedBox(height: 14),

              Text(
                'Description',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 5),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: _decoration('What is on offer, and until when?'),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Images',
                      style: AppTextStyles.body.copyWith(fontSize: 12.5),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _uploading ? null : _addImage,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 16,
                    ),
                    label: const Text('Upload'),
                  ),
                ],
              ),
              if (_available.isEmpty)
                Text(
                  'This project has no images yet. Upload one to include it.',
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final url in _available)
                      _ImageTile(
                        url: url,
                        selected: _selected.contains(url),
                        onTap: () => setState(() {
                          if (!_selected.remove(url)) _selected.add(url);
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Video',
                      style: AppTextStyles.body.copyWith(fontSize: 12.5),
                    ),
                  ),
                  if (_videoUrl != null)
                    TextButton(
                      onPressed: _uploading
                          ? null
                          : () => setState(() => _videoUrl = null),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Remove'),
                    ),
                  TextButton.icon(
                    onPressed: _uploading ? null : _addVideo,
                    icon: const Icon(Icons.videocam_outlined, size: 16),
                    label: Text(_videoUrl == null ? 'Upload' : 'Replace'),
                  ),
                ],
              ),
              Text(
                _videoUrl == null
                    ? 'Optional. Maximum 50 MB.'
                    : 'A video is attached.',
                style: AppTextStyles.caption.copyWith(fontSize: 11.5),
              ),

              if (_uploading) ...[
                const SizedBox(height: 12),
                const BuilderActionBusyRow(),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _uploading
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _uploading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isEditing ? 'Save Changes' : 'Market Offer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.hairline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.hairline),
    ),
  );
}

/// One selectable image, ticked when included in the offer.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.url,
    required this.selected,
    required this.onTap,
  });

  static const double _size = 66;

  final String url;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? 'Image included' : 'Image not included',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(
                AppConstants.imageThumbnailRadius,
              ),
              child: Container(
                width: _size,
                height: _size,
                color: AppColors.primaryLight,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.image_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.check, size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
