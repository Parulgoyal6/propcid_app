// screens/add_project/steps/contact_media_step.dart
//
// Step 3 of 5 — `renderStep3` in `BuilderProjectWizard.tsx`.
//
// EVERY FIELD HERE IS REQUIRED
// ----------------------------
// `mediaRules` (`projectRules.ts:63-71`) requires the contact number, the
// logo, a master-plan layout, the brochure PDF, at least one project image
// and at least one video. That is a heavy ask on a phone, and it is the
// reference's rule — kept as decision D5, because relaxing it would let this app
// create projects the portal would reject.
//
// A Website URL field used to sit above Contact Number here, required the
// same way. Removed by request to match the portal: `renderStep3` never
// collects a website at all, and current `projectRules.ts` no longer lists
// one either. `ProjectDraft.websiteUrl`/`kProjectWebsiteUrl` and the submit
// payload are untouched — any value a project already carries (from
// elsewhere) still loads, saves and displays exactly as before; only this
// step's input and required-ness were removed.
//
// The brochure is why `file_picker` is a dependency (decision D3): `image_picker`
// cannot select a PDF, and `brochure_url` is mandatory.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/add_project_provider.dart';
import '../../../services/project_media_service.dart';
import '../../post_property/portal_icon.dart';
import '../../post_property/portal_kit.dart';
import '../project_field_keys.dart';

/// Dimensions the pickers downscale to before upload.
///
/// The reference compresses with `compressMedia` before every upload; the app's
/// established equivalent is `image_picker`'s own sizing, which is what
/// `ProfileMediaService` uses. A master-plan layout gets the largest budget
/// because it carries fine print a buyer needs to read.
const double _kLogoMaxDimension = 1024;
const double _kLayoutMaxDimension = 2560;
const double _kPhotoMaxDimension = 1920;
const int _kJpegQuality = 85;

class ContactMediaStep extends StatefulWidget {
  const ContactMediaStep({super.key});

  @override
  State<ContactMediaStep> createState() => _ContactMediaStepState();
}

class _ContactMediaStepState extends State<ContactMediaStep> {
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _contact;

  @override
  void initState() {
    super.initState();
    final d = context.read<AddProjectProvider>().draft;
    _contact = TextEditingController(text: d.contactNumber);
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  void _report(Object error) {
    if (!mounted) return;
    // A ProjectMediaException's message is written for exactly this; anything
    // else gets a generic line rather than a raw exception string.
    final message = error is ProjectMediaException
        ? error.message
        : 'Upload failed. Please try again.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickImage({
    required double maxDimension,
    required Future<void> Function(Uint8List, String) upload,
  }) async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: _kJpegQuality,
      );
      if (file == null) return;
      await upload(await file.readAsBytes(), file.name);
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _pickImages() async {
    try {
      final files = await _picker.pickMultiImage(
        maxWidth: _kPhotoMaxDimension,
        maxHeight: _kPhotoMaxDimension,
        imageQuality: _kJpegQuality,
      );
      if (files.isEmpty) return;
      if (!mounted) return;
      final provider = context.read<AddProjectProvider>();
      // Sequential, like the reference's `for (const file of files)` loop — a
      // parallel burst of large uploads on mobile data is worse than a queue.
      for (final file in files) {
        await provider.uploadImage(await file.readAsBytes(), file.name);
      }
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final provider = context.read<AddProjectProvider>();
      await provider.uploadVideo(await file.readAsBytes(), file.name);
    } catch (e) {
      _report(e);
    }
  }

  /// The one picker `image_picker` cannot provide.
  Future<void> _pickBrochure() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        // Needed because the upload takes bytes; on Android a content URI has no
        // usable path.
        withData: true,
      );
      final file = result?.files.singleOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null || !mounted) return;
      final provider = context.read<AddProjectProvider>();
      await provider.uploadBrochure(bytes, file.name);
    } catch (e) {
      _report(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AddProjectProvider>();
    final draft = provider.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PortalStepHeader(
          icon: 'phone',
          title: 'Contact & Media',
          subtitle: 'How buyers reach you, and what they will see',
        ),
        const SizedBox(height: 20),

        if (provider.stepIssues.isNotEmpty) ...[
          PortalValidationSummary(
            messages: provider.stepIssues
                .map((issue) => issue.message)
                .toList(),
          ),
          const SizedBox(height: 16),
        ],

        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortalSectionDivider(icon: 'phone', title: 'Contact'),
              const SizedBox(height: 14),
              PortalLabelledField(
                label: 'Contact Number',
                required: true,
                icon: 'phone',
                child: PortalTextField(
                  controller: _contact,
                  hint: '10-digit mobile number',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  hasError: provider.hasIssue(kProjectContactNumber),
                  onChanged: provider.setContactNumber,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortalSectionDivider(icon: 'image', title: 'Media'),
              const SizedBox(height: 14),

              _SingleAsset(
                label: 'Project Logo',
                icon: 'image',
                url: draft.logoUrl,
                hasError: provider.hasIssue(kProjectLogoUrl),
                busy: provider.isUploading(ProjectUploadSlot.logo),
                onPick: () => _pickImage(
                  maxDimension: _kLogoMaxDimension,
                  upload: provider.uploadLogo,
                ),
                onClear: provider.clearLogo,
              ),
              const SizedBox(height: 18),

              _AssetList(
                label: 'Master Plan Layout',
                icon: 'map',
                helper:
                    'The first layout you add becomes the project\'s master '
                    'plan.',
                urls: draft.mapImages,
                hasError: provider.hasIssue(kProjectMapImages),
                busy: provider.isUploading(ProjectUploadSlot.masterLayout),
                addLabel: 'Add layout',
                onAdd: () => _pickImage(
                  maxDimension: _kLayoutMaxDimension,
                  upload: provider.uploadMasterLayout,
                ),
                onRemove: provider.removeMapImage,
              ),
              const SizedBox(height: 18),

              _AssetList(
                label: 'Project Images',
                icon: 'image-plus',
                urls: draft.otherImages,
                hasError: provider.hasIssue(kProjectOtherImages),
                busy: provider.isUploading(ProjectUploadSlot.images),
                addLabel: 'Add images',
                onAdd: _pickImages,
                onRemove: provider.removeOtherImage,
              ),
              const SizedBox(height: 18),

              _AssetList(
                label: 'Project Videos',
                icon: 'video',
                helper: 'Up to 500 MB each.',
                urls: draft.videosUrls,
                hasError: provider.hasIssue(kProjectVideosUrls),
                busy: provider.isUploading(ProjectUploadSlot.videos),
                addLabel: 'Add video',
                isVideo: true,
                onAdd: _pickVideo,
                onRemove: provider.removeVideo,
              ),
              const SizedBox(height: 18),

              _SingleAsset(
                label: 'Project Brochure (PDF)',
                icon: 'file-text',
                url: draft.brochureUrl,
                hasError: provider.hasIssue(kProjectBrochureUrl),
                busy: provider.isUploading(ProjectUploadSlot.brochure),
                isDocument: true,
                onPick: _pickBrochure,
                onClear: provider.clearBrochure,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A slot that holds exactly one asset — the logo, or the brochure.
class _SingleAsset extends StatelessWidget {
  const _SingleAsset({
    required this.label,
    required this.icon,
    required this.url,
    required this.hasError,
    required this.busy,
    required this.onPick,
    required this.onClear,
    this.isDocument = false,
  });

  final String label;
  final String icon;
  final String url;
  final bool hasError;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final bool isDocument;

  @override
  Widget build(BuildContext context) {
    final hasAsset = url.isNotEmpty;

    return PortalLabelledField(
      label: label,
      required: true,
      icon: icon,
      child: hasAsset
          ? _FilledSlot(url: url, isDocument: isDocument, onClear: onClear)
          : _UploadButton(
              label: isDocument ? 'Choose PDF' : 'Upload',
              busy: busy,
              hasError: hasError,
              onTap: onPick,
            ),
    );
  }
}

/// A slot that holds any number of assets — layouts, images, videos.
class _AssetList extends StatelessWidget {
  const _AssetList({
    required this.label,
    required this.icon,
    required this.urls,
    required this.hasError,
    required this.busy,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
    this.helper,
    this.isVideo = false,
  });

  final String label;
  final String icon;
  final List<String> urls;
  final bool hasError;
  final bool busy;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String? helper;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return PortalLabelledField(
      label: label,
      required: true,
      icon: icon,
      helper: helper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urls.isNotEmpty) ...[
            // Horizontal so a long list never pushes the rest of the step down.
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _Thumb(
                  url: urls[i],
                  isVideo: isVideo,
                  onRemove: () => onRemove(i),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _UploadButton(
            label: addLabel,
            busy: busy,
            hasError: hasError && urls.isEmpty,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.label,
    required this.busy,
    required this.hasError,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hasError
              ? AppColors.error.withValues(alpha: 0.04)
              : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasError ? AppColors.error : AppColors.hairline,
            width: hasError ? 1.4 : 1,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PortalIcon(
                    'upload',
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A filled single-asset slot: a preview (or a document row) plus a remove
/// control.
class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.url,
    required this.isDocument,
    required this.onClear,
  });

  final String url;
  final bool isDocument;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          if (isDocument)
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const PortalIcon(
                'file-text',
                size: 18,
                color: AppColors.primary,
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _RemoteThumb(url: url, size: 40),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isDocument ? 'Brochure uploaded' : 'Uploaded',
              style: AppTextStyles.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.close_rounded,
                size: 17,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.isVideo,
    required this.onRemove,
  });

  final String url;
  final bool isVideo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isVideo
                  // A video has no still to show without decoding a frame, so
                  // the slot is labelled rather than left blank.
                  ? Container(
                      color: AppColors.primaryLight,
                      alignment: Alignment.center,
                      child: const PortalIcon(
                        'video',
                        size: 20,
                        color: AppColors.primary,
                      ),
                    )
                  : _RemoteThumb(url: url, size: 76),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A network thumbnail that degrades to a tinted placeholder.
class _RemoteThumb extends StatelessWidget {
  const _RemoteThumb({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: size,
      height: size,
      color: AppColors.primaryLight,
      alignment: Alignment.center,
      child: const PortalIcon('image', size: 16, color: AppColors.primary),
    );

    if (url.isEmpty) return placeholder();

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder(),
    );
  }
}
