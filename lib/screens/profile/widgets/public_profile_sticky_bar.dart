// screens/profile/widgets/public_profile_sticky_bar.dart
//
// The persistent action bar at the bottom of the Public Profile screen.
//
// GEOMETRY BORROWED FROM PROPERTY DETAIL
// --------------------------------------
// 72 dp, `cardBackground`, a 0.5 dp `textHint` top border, 16 x 10 padding — the
// exact bar `property_detail_screen.dart:1305` uses. That is the app's only other
// "pushed detail screen with a persistent CTA", so matching it makes this screen
// feel like part of the same app.
//
// (`AppConstants.stickyBottomBarHeight` is 64 and `bottomActionBarHeight` is 60,
// but property detail uses a literal 72 and neither constant is referenced
// anywhere. Following the shipped screen rather than an unused constant.)
//
// STAGE 1 IS READ-ONLY
// --------------------
// The connect button renders all four states from the resolved status, but
// tapping it is Phase 6. `onConnect` is null here, which paints the button
// disabled rather than showing an affordance that does nothing.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../services/profile_connection_service.dart';
import '../../../widgets/shared/app_action_button.dart';

/// Height of the bar itself, excluding the safe-area inset.
const double kProfileStickyBarHeight = 72;

class ProfileStickyActionBar extends StatelessWidget {
  /// Viewing your own profile — the bar becomes Share only (Edit Profile arrives
  /// with Phase 3's edit screen; showing it now would be a dead end).
  final bool isSelf;

  final bool viewerSignedIn;
  final ProfileConnectionStatus connectionStatus;

  /// Hides the connect control while the status is still resolving, so it cannot
  /// flash the wrong state.
  final bool statusLoading;

  final VoidCallback onShare;

  /// Null while Phase 6 is unimplemented — renders the state, disables the tap.
  final VoidCallback? onConnect;

  /// Null when there is no viewer to message with.
  final VoidCallback? onMessage;

  /// Non-null only when exactly one of {viewer, viewed profile} is an
  /// influencer and the viewer isn't looking at themselves — the
  /// Collaboration Marketplace entry point (`UserProfile.tsx`'s
  /// `canCollaborate`). Null hides the button entirely rather than
  /// disabling it.
  final VoidCallback? onCollaborate;

  /// True when a `requested`-status collaboration already exists between
  /// the viewer and this profile — `UserProfile.tsx`'s duplicate-request
  /// guard. Swaps the button to "Requested" instead of letting a second
  /// request be sent for the same pair; [onCollaborate] still fires (it
  /// opens/focuses the existing request rather than a new one).
  final bool collabRequested;

  /// Prompts sign-in for an anonymous viewer.
  final VoidCallback? onSignIn;

  const ProfileStickyActionBar({
    super.key,
    required this.isSelf,
    required this.viewerSignedIn,
    required this.connectionStatus,
    required this.statusLoading,
    required this.onShare,
    this.onConnect,
    this.onMessage,
    this.onCollaborate,
    this.collabRequested = false,
    this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kProfileStickyBarHeight + MediaQuery.paddingOf(context).bottom,
      padding: EdgeInsets.only(
        left: AppConstants.spacingL,
        right: AppConstants.spacingL,
        top: 10,
        bottom: 10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(top: BorderSide(color: AppColors.textHint, width: 0.5)),
      ),
      child: _buildActions(),
    );
  }

  Widget _buildActions() {
    if (isSelf) {
      return AppActionButton(
        label: 'Share your profile',
        icon: Icons.share_outlined,
        variant: AppActionButtonVariant.solid,
        elevated: true,
        height: 46,
        onTap: onShare,
      );
    }

    if (!viewerSignedIn) {
      return AppActionButton(
        label: 'Sign in to connect',
        variant: AppActionButtonVariant.solid,
        elevated: true,
        height: 46,
        onTap: onSignIn,
      );
    }

    final collaborate = onCollaborate;
    return Row(
      children: [
        Expanded(
          child: ConnectActionButton(
            status: connectionStatus,
            isLoading: statusLoading,
            onTap: onConnect,
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: AppActionButton(
            label: collaborate != null ? 'Chat' : 'Message',
            icon: Icons.chat_bubble_outline_rounded,
            variant: AppActionButtonVariant.solid,
            elevated: true,
            height: 46,
            onTap: onMessage,
          ),
        ),
        if (collaborate != null) ...[
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: AppActionButton(
              label: collabRequested ? 'Requested' : 'Collab',
              icon: collabRequested
                  ? Icons.schedule_rounded
                  : Icons.handshake_outlined,
              variant: AppActionButtonVariant.outline,
              height: 46,
              onTap: collaborate,
            ),
          ),
        ],
      ],
    );
  }
}

/// One control expressing all four connection states.
///
/// Colour, border, icon and label morph over 300 ms rather than swapping between
/// four separate buttons, so the transition after Phase 6 wires the actions reads
/// as the same object changing state.
///
/// The connected state uses a **tinted fill with a green label**, not white on
/// green: white on `success` (#22C55E) is 2.3:1, which fails WCAG AA.
class ConnectActionButton extends StatelessWidget {
  final ProfileConnectionStatus status;
  final bool isLoading;
  final VoidCallback? onTap;

  const ConnectActionButton({
    super.key,
    required this.status,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(status);
    final enabled = onTap != null && !isLoading && spec.tappable;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: AppConstants.animationDurationMs),
      curve: Curves.easeOutCubic,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
      decoration: BoxDecoration(
        color: spec.fill,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        border: spec.border == null
            ? null
            : Border.all(color: spec.border!, width: 1.5),
        boxShadow: spec.elevated ? AppColors.primaryActionShadow : null,
      ),
      child: Center(
        child: isLoading
            // Fixed 16 dp so the bar's width never reflows mid-request.
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(spec.foreground),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(spec.icon, size: 16, color: spec.foreground),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      spec.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.button.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: spec.foreground,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );

    final labelled = Semantics(
      label: isLoading ? 'Updating connection' : spec.semanticLabel,
      button: enabled,
      enabled: enabled,
      child: ExcludeSemantics(child: body),
    );

    if (!enabled) return Opacity(opacity: 0.75, child: labelled);
    return ScaleTap(onTap: onTap, child: labelled);
  }

  static _ConnectSpec _specFor(ProfileConnectionStatus status) {
    switch (status) {
      case ProfileConnectionStatus.none:
        return const _ConnectSpec(
          label: 'Connect',
          semanticLabel: 'Connect with this user',
          icon: Icons.person_add_alt_1_rounded,
          fill: AppColors.primary,
          foreground: Colors.white,
          elevated: true,
          tappable: true,
        );
      case ProfileConnectionStatus.pendingSent:
        return const _ConnectSpec(
          label: 'Requested',
          semanticLabel: 'Connection requested. Tap to cancel',
          icon: Icons.schedule_rounded,
          fill: Color(0x1FF97316),
          border: AppColors.warning,
          foreground: AppColors.warning,
          tappable: true,
        );
      case ProfileConnectionStatus.pendingReceived:
        return const _ConnectSpec(
          label: 'Accept',
          semanticLabel: 'Accept connection request',
          icon: Icons.check_rounded,
          fill: AppColors.success,
          foreground: Colors.white,
          elevated: true,
          tappable: true,
        );
      case ProfileConnectionStatus.connected:
        return const _ConnectSpec(
          label: 'Connected',
          semanticLabel: 'You are connected',
          icon: Icons.how_to_reg_rounded,
          fill: Color(0x1F22C55E),
          border: AppColors.success,
          foreground: AppColors.success,
          tappable: false,
        );
    }
  }
}

@immutable
class _ConnectSpec {
  final String label;
  final String semanticLabel;
  final IconData icon;
  final Color fill;
  final Color? border;
  final Color foreground;
  final bool elevated;

  /// The connected state is terminal — there is nothing to do from it.
  final bool tappable;

  const _ConnectSpec({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.fill,
    required this.foreground,
    this.border,
    this.elevated = false,
    this.tappable = true,
  });
}
