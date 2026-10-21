import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/profile_link.dart';
import '../../../core/widgets/scale_tap.dart';

/// Share the user's public profile (blueprint §16.10).
///
/// The URL is built by [profileShareUrl], a port of the portal's
/// `profilePath` — not an invented scheme. Sharing uses `share_plus`, already
/// a dependency and already used the same way in `reels_screen.dart`.
///
/// The web modal also renders and attaches a visiting-card PNG via `<canvas>`;
/// that generation is out of scope here, so mobile shares the formatted text
/// and link, which is what §16.10's acceptance criterion asks for.
void showShareProfileSheet(
  BuildContext context, {
  required String? userId,
  required String name,
  required String? userType,
  String? city,
  double? rating,
  int? reviewsCount,
}) {
  final shareUrl = profileShareUrl(userId: userId, name: name, role: userType);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareProfileBody(
      shareUrl: shareUrl,
      message: profileShareMessage(
        name: name,
        userType: userType,
        shareUrl: shareUrl,
        city: city,
        rating: rating,
        reviewsCount: reviewsCount,
      ),
    ),
  );
}

class _ShareProfileBody extends StatelessWidget {
  final String shareUrl;
  final String message;

  const _ShareProfileBody({required this.shareUrl, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEDF2),
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share Profile',
              style: AppTextStyles.heading3.copyWith(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ProfileLinkBox(shareUrl: shareUrl),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ShareActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy Link',
                    filled: false,
                    onTap: () => copyProfileLink(context, shareUrl),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ShareActionButton(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    filled: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      // Same call shape as reels_screen.dart.
                      Share.share(message, subject: 'PropCid Profile');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only display of the profile URL.
class ProfileLinkBox extends StatelessWidget {
  final String shareUrl;

  const ProfileLinkBox({super.key, required this.shareUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
      ),
      child: Text(
        shareUrl,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Copies [shareUrl] and confirms with a snackbar.
Future<void> copyProfileLink(BuildContext context, String shareUrl) async {
  await Clipboard.setData(ClipboardData(text: shareUrl));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
}

/// Pill button used by the Share and QR sheets.
class ShareActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const ShareActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            boxShadow: filled ? AppColors.primaryActionShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: filled ? Colors.white : AppColors.primary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTextStyles.button.copyWith(
                  fontSize: 13.5,
                  color: filled ? Colors.white : AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
