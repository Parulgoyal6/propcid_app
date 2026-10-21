import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/reel_model.dart';
import '../../../services/messaging_service.dart';
import '../../messaging/widgets/send_to_user_flow.dart';
import '../../profile/actions/share_profile_sheet.dart'
    show ProfileLinkBox, ShareActionButton, copyProfileLink;

/// Share a reel — mirrors the portal's PropertyShareModal
/// (`src/components/ShareToSocial.tsx`, `data.type: 'video'`), the exact same
/// component the property share sheet is ported from: native share, "Send to
/// a user" (video is the other of the two content types `canSendToUser`
/// allows — see `share_property_sheet.dart`'s equivalent comment), the same 4
/// social buttons, and a visible/copyable link. Reels previously only opened
/// the bare OS share sheet with no modal of their own at all.
void showShareReelSheet(
  BuildContext context, {
  required ReelModel reel,
  required String? currentUserId,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // Scrollable rather than overflowing on shorter screens — see the same
    // note in share_property_sheet.dart.
    isScrollControlled: true,
    builder: (_) => _ShareReelBody(reel: reel, currentUserId: currentUserId),
  );
}

class _ShareReelBody extends StatelessWidget {
  final ReelModel reel;
  final String? currentUserId;

  const _ShareReelBody({required this.reel, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final String displayTitle = reel.title.isNotEmpty
        ? reel.title
        : 'Check out this reel';
    final String shareUrl = reel.shareUrl;
    final String message = reel.shareMessage;

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
        child: SingleChildScrollView(
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
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Share Reel',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
              if (reel.hasPrice || reel.hasLocation) ...[
                const SizedBox(height: 2),
                Text(
                  [
                    if (reel.hasPrice) reel.price,
                    if (reel.hasLocation) reel.location,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ShareActionButton(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                filled: true,
                onTap: () {
                  Navigator.of(context).pop();
                  Share.share(message, subject: displayTitle);
                },
              ),
              if (currentUserId != null) ...[
                const SizedBox(height: 10),
                ShareActionButton(
                  icon: Icons.send_rounded,
                  label: 'Send to a user',
                  filled: false,
                  onTap: () => runSendToUserFlow(
                    context,
                    currentUserId: currentUserId!,
                    onSend: (conversationId) =>
                        MessagingService().sendReelShare(
                          threadId: conversationId,
                          senderId: currentUserId!,
                          reelId: reel.id,
                          content: 'Shared reel: $displayTitle',
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SocialButton(
                      icon: Icons.message_rounded,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: () => _openSocial(
                        context,
                        'https://wa.me/?text=${Uri.encodeComponent(message)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SocialButton(
                      icon: Icons.facebook_rounded,
                      label: 'Facebook',
                      color: const Color(0xFF1877F2),
                      onTap: () => _openSocial(
                        context,
                        'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(shareUrl)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SocialButton(
                      icon: Icons.alternate_email_rounded,
                      label: 'Twitter',
                      color: const Color(0xFF1DA1F2),
                      onTap: () => _openSocial(
                        context,
                        'https://twitter.com/intent/tweet?text=${Uri.encodeComponent(message)}&url=${Uri.encodeComponent(shareUrl)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SocialButton(
                      icon: Icons.business_center_rounded,
                      label: 'LinkedIn',
                      color: const Color(0xFF0A66C2),
                      onTap: () => _openSocial(
                        context,
                        'https://www.linkedin.com/sharing/share-offsite/?url=${Uri.encodeComponent(shareUrl)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ProfileLinkBox(shareUrl: shareUrl),
              const SizedBox(height: 10),
              ShareActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy Link',
                filled: false,
                onTap: () => copyProfileLink(context, shareUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSocial(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ShareReelSheet] Failed to open $url: $e');
    }
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 6),
              Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
