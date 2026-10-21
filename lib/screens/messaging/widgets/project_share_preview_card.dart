import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/shared_project_preview.dart';

/// Rich card for a received `project_share` message - title, location and a
/// short description with a "View Project" action, instead of the plain
/// "Shared project: ..." text. Mirrors the portal's `ProjectShareMessage`
/// (project title + description + location) and is the same visual family
/// as [PropertySharePreviewCard] / [ReelSharePreviewCard].
///
/// [project] is null while the lookup in [ChatThreadProvider] is still in
/// flight, or if the project can't be loaded - then [fallbackText] (the
/// message's own content, as the portal does) is shown instead of a blank
/// bubble.
class ProjectSharePreviewCard extends StatelessWidget {
  final SharedProjectPreview? project;
  final String fallbackText;
  final bool isMine;

  const ProjectSharePreviewCard({
    super.key,
    required this.project,
    required this.fallbackText,
    required this.isMine,
  });

  void _openProject(BuildContext context) {
    final id = project?.id;
    if (id == null || id.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    final foreground = isMine ? Colors.white : AppColors.textPrimary;
    final subForeground = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textSecondary;

    if (p == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isMine ? Colors.white : AppColors.textHint).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apartment_rounded, size: 18, color: subForeground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  fallbackText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    color: subForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasDescription = p.description?.trim().isNotEmpty ?? false;
    final hasLocation = p.location?.trim().isNotEmpty ?? false;

    return GestureDetector(
      onTap: () => _openProject(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isMine ? Colors.white : AppColors.background).withValues(
              alpha: 0.14,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.22)
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.apartment_rounded,
                      size: 17,
                      color: isMine ? Colors.white : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.title.isNotEmpty ? p.title : 'Project',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasLocation) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 13,
                      color: subForeground,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        p.location!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 11.5,
                          color: subForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (hasDescription) ...[
                const SizedBox(height: 6),
                Text(
                  p.description!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    color: subForeground,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isMine ? Colors.white : AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'View Project',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isMine ? AppColors.primary : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
