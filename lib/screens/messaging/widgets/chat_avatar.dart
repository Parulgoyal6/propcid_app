import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Circular avatar with an initials fallback, shared by the conversation list,
/// the channel list and both thread headers.
class ChatAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;

  const ChatAvatar({
    super.key,
    required this.avatarUrl,
    required this.initials,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials,
        style: AppTextStyles.body.copyWith(
          fontSize: size * 0.29,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? fallback
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorWidget: (_, _, _) => fallback,
              ),
            ),
    );
  }
}
