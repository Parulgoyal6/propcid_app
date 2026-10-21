// widgets/project_card_vertical.dart
//
// A builder *project* card — [ProjectModel], not [PropertyModel]. Deliberately
// a separate widget from `PropertyCardVertical` rather than a reused/adapted
// one: a project has a price *range* and unit counts instead of a single
// price and beds/baths, and taps go to `/project-detail`, not
// `/property-detail`. Sharing a card between the two data shapes is exactly
// the property/project mixing the Home rails must avoid.
//
// Reuses `ProjectStatusPill` and `projectPriceRangeLabel` from the builder
// dashboard's project card rather than duplicating that formatting — both are
// pure, side-effect-free presentation helpers already proven against
// [ProjectModel].
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/scale_tap.dart';
import '../core/widgets/shimmer_loader.dart';
import '../models/project_model.dart';
import '../screens/dashboard/widgets/my_projects_section.dart'
    show ProjectStatusPill, projectPriceRangeLabel;

class ProjectCardVertical extends StatelessWidget {
  const ProjectCardVertical({
    super.key,
    required this.project,
    this.onTap,
    double? width,
    double? imageHeight,
    this.imageCacheWidth,
    this.imageCacheHeight,
  }) : width = width ?? AppConstants.propertyCardWidth,
       imageHeight = imageHeight ?? AppConstants.propertyCardImageHeight;

  final ProjectModel project;
  final VoidCallback? onTap;
  final double width;
  final double imageHeight;

  /// Bounds the decoded cover image to roughly this many physical pixels
  /// (`memCacheWidth`/`memCacheHeight` on the underlying
  /// `CachedNetworkImage`) instead of the source's native resolution. Null
  /// by default so the one non-Home caller
  /// (`screens/project/latest_projects_screen.dart`) keeps its exact
  /// current behaviour untouched; only the Home rails pass a value.
  final int? imageCacheWidth;
  final int? imageCacheHeight;

  @override
  Widget build(BuildContext context) {
    // Same 16 dp gap as the old margin, moved outside ScaleTap so the press
    // glow hugs the card rather than the gap beside it.
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ScaleTap(
      onTap: onTap,
      scaleDown: 0.97,
      glowRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.cardShadow,
        ),
        // Thin frosted-glass edge for depth, drawn over the content.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppConstants.cardRadius),
                    topRight: Radius.circular(AppConstants.cardRadius),
                  ),
                  child: project.coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: project.coverImage!,
                          width: width,
                          height: imageHeight,
                          fit: BoxFit.cover,
                          memCacheWidth: imageCacheWidth,
                          memCacheHeight: imageCacheHeight,
                          // Shimmer while loading; the static placeholder
                          // stays for errors / no image.
                          placeholder: (_, _) => SizedBox(
                            width: width,
                            height: imageHeight,
                            child: const ShimmerBox(),
                          ),
                          errorWidget: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: ProjectStatusPill(status: project.status),
                ),
                if (project.reraNumber.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.verifiedBadge,
                        borderRadius: BorderRadius.circular(
                          AppConstants.chipRadius,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'RERA',
                            style: AppTextStyles.chip.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            project.location,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    project.typeLabel,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (project.totalUnits > 0)
                    Row(
                      children: [
                        const Icon(
                          Icons.apartment_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${project.availableUnits}/${project.totalUnits} units',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          project.hasPriceRange
                              ? projectPriceRangeLabel(project)
                              : 'Price on Request',
                          style: AppTextStyles.price.copyWith(fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: onTap,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: width,
    height: imageHeight,
    color: AppColors.primaryLight,
    alignment: Alignment.center,
    child: const Icon(
      Icons.apartment_rounded,
      size: 28,
      color: AppColors.primary,
    ),
  );
}
