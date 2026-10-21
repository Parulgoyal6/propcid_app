import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/property_model.dart';
import '../../../widgets/status_tag.dart';
import 'property_card_facts.dart';

const double _kSheetRadius = 24;
const double _kHandleWidth = 36;
const double _kHandleHeight = 4;
const double _kImageHeight = 150;
const double _kButtonHeight = 48;

/// Opens the map's quick-preview sheet for [property].
///
/// Returns true when the user pressed "View Details", so the caller can
/// navigate — the sheet itself never routes anywhere. Returns false for a scrim
/// tap, a swipe-down or a back gesture.
///
/// Modal on purpose: the redesign draws this over a scrim, and that scrim is
/// what makes "tap the map to dismiss and deselect" work without the map widget
/// needing to expose an `onTap`.
Future<bool> showPropertyQuickPreview(
  BuildContext context,
  PropertyModel property,
) async {
  final bool? viewDetails = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (sheetContext) => _QuickPreviewSheet(property: property),
  );
  return viewDetails ?? false;
}

/// The redesign's single-state preview: image, price, title, locality, facts,
/// and one full-width action.
///
/// A new widget rather than an extension of `widgets/map_property_summary_card.dart`.
/// That card is a 130x95 image row sized to overlay the map; this is a
/// full-width sheet with a 150 dp hero image and a primary CTA — a different
/// component, not a variant. The summary card is left untouched.
///
/// Single state, not the peek/expanded pair the build plan sketches: the
/// redesign draws exactly one height, and everything its "expanded" state was
/// meant to add (a prominent View Details) is already here.
class _QuickPreviewSheet extends StatelessWidget {
  final PropertyModel property;

  const _QuickPreviewSheet({required this.property});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingXL,
          10,
          AppConstants.spacingXL,
          AppConstants.spacingXXL,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: _kHandleWidth,
                height: _kHandleHeight,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
              ),
            ),
            _buildImage(),
            const SizedBox(height: 14),
            Text(
              property.priceDisplay,
              style: AppTextStyles.price.copyWith(fontSize: 22),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppConstants.spacingXS),
            Text(
              property.title,
              style: AppTextStyles.body.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              property.location,
              style: AppTextStyles.caption.copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.bed, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    propertyFactsLine(property),
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildViewDetailsButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: SizedBox(
        height: _kImageHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: property.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  ColoredBox(color: AppColors.textHint.withValues(alpha: 0.1)),
              errorWidget: (context, url, error) => ColoredBox(
                color: AppColors.textHint.withValues(alpha: 0.1),
                child: const Icon(Icons.broken_image, size: 24),
              ),
            ),
            if (property.statusTags.isNotEmpty)
              Positioned(
                top: 10,
                left: 10,
                child: StatusTag(label: property.statusTags.first),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewDetailsButton(BuildContext context) {
    return Semantics(
      label: 'View details',
      button: true,
      child: GestureDetector(
        onTap: () => Navigator.pop(context, true),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _kButtonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            boxShadow: AppColors.primaryActionShadow,
          ),
          child: Text(
            'View Details',
            style: AppTextStyles.button.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
