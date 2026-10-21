import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../profile_role.dart';

/// Display name + role pill + @handle (blueprint §4.1).
class ProfileIdentityBlock extends StatelessWidget {
  final String displayName;

  /// `profiles.username`. The handle line is omitted entirely when the column
  /// is empty rather than showing a fabricated placeholder.
  final String? username;

  final String? userType;

  const ProfileIdentityBlock({
    super.key,
    required this.displayName,
    required this.username,
    required this.userType,
  });

  @override
  Widget build(BuildContext context) {
    final handle = username?.trim();
    final label = roleLabel(userType);
    final tint = roleColor(userType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              displayName.isNotEmpty ? displayName : 'Your profile',
              style: AppTextStyles.heading1.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
              decoration: BoxDecoration(
                // Role tinting is kept so Builder/Broker/Influencer stay
                // distinguishable at a glance.
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tint.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 13, color: tint),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (handle != null && handle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            handle.startsWith('@') ? handle : '@$handle',
            style: AppTextStyles.caption.copyWith(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
