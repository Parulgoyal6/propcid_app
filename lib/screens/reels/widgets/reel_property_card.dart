import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/reel_model.dart';

/// Property-details block shown below the video, matching the reference
/// design: title + featured badge, location, price + status.
///
/// In its default (non-[compact]) form it also renders a spec row (area /
/// bedrooms / bathrooms / parking) and up to 4 property highlights — used
/// by the video~62%/card~38% layout. The video~80%/card~20% compact layout
/// only has room for title/location/price, so [compact] skips straight
/// past the specs/highlights sections instead of duplicating this widget.
class ReelPropertyCard extends StatelessWidget {
  const ReelPropertyCard({super.key, required this.reel, this.compact = false});

  final ReelModel reel;

  /// When true, renders only the title/location/price+status block —
  /// skips the specs row and highlights section entirely, regardless of
  /// whether the reel has that data.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTitleRow(),
        if (reel.hasLocation) ...[
          SizedBox(height: compact ? 4 : 6),
          _buildLocationRow(),
        ],
        if (reel.hasPrice || reel.hasStatus) ...[
          SizedBox(height: compact ? 8 : 12),
          _buildPriceRow(),
        ],
        if (!compact && reel.hasSpecs) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _buildSpecsRow(),
        ],
        if (!compact && reel.highlights.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            'Property Highlights',
            style: AppTextStyles.heading3.copyWith(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _buildHighlightsRow(),
        ],
      ],
    );
  }

  Widget _buildTitleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            reel.title.isNotEmpty ? reel.title : 'Featured Property',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 18 : 20,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationRow() {
    return Row(
      children: [
        Icon(
          Icons.location_on_outlined,
          color: AppColors.textPrimary.withOpacity(0.55),
          size: 15,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            reel.location!,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textPrimary.withOpacity(0.65),
              fontSize: compact ? 13 : 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow() {
    return Row(
      children: [
        if (reel.hasPrice)
          Text(
            reel.price!,
            style: AppTextStyles.price.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 20 : 24,
            ),
          ),
        if (reel.hasPrice && reel.hasStatus) const SizedBox(width: 10),
        if (reel.hasStatus) _StatusBadge(label: reel.status!),
      ],
    );
  }

  Widget _buildSpecsRow() {
    final items = <Widget>[
      if (reel.areaLabel != null)
        _SpecItem(
          icon: Icons.crop_square_rounded,
          value: reel.areaLabel!,
          label: reel.areaUnit,
        ),
      if (reel.bedrooms != null)
        _SpecItem(
          icon: Icons.bed_outlined,
          value: '${reel.bedrooms}',
          label: reel.bedrooms == 1 ? 'Bedroom' : 'Bedrooms',
        ),
      if (reel.bathrooms != null)
        _SpecItem(
          icon: Icons.bathtub_outlined,
          value: '${reel.bathrooms}',
          label: reel.bathrooms == 1 ? 'Bathroom' : 'Bathrooms',
        ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items,
    );
  }

  Widget _buildHighlightsRow() {
    final highlights = reel.highlights.take(4).toList();
    return Row(
      children: [
        for (int i = 0; i < highlights.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _HighlightItem(label: highlights[i])),
        ],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    // Swap Colors.green for your theme's success token if you have one
    // (e.g. AppColors.success) to stay fully on-brand.
    const Color success = Color(0xFF1E9E5A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.chip.copyWith(
          color: success,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SpecItem extends StatelessWidget {
  const _SpecItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textPrimary.withOpacity(0.55),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _HighlightItem extends StatelessWidget {
  const _HighlightItem({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _iconFor(label),
          size: 18,
          color: AppColors.textPrimary.withOpacity(0.7),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary.withOpacity(0.8),
              fontSize: 12,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Best-effort icon for a highlight label. Falls back to a generic check
  /// icon for anything unrecognized — highlight *text* always comes from the
  /// reel/provider, never hardcoded here.
  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('kitchen')) return Icons.kitchen_outlined;
    if (l.contains('power') || l.contains('backup')) {
      return Icons.bolt_rounded;
    }
    if (l.contains('security')) return Icons.shield_outlined;
    if (l.contains('club') || l.contains('house')) {
      return Icons.apartment_rounded;
    }
    if (l.contains('gym') || l.contains('fitness')) {
      return Icons.fitness_center_rounded;
    }
    if (l.contains('pool') || l.contains('swim')) {
      return Icons.pool_rounded;
    }
    if (l.contains('lift') || l.contains('elevator')) {
      return Icons.elevator_outlined;
    }
    if (l.contains('garden') || l.contains('park')) {
      return Icons.park_outlined;
    }
    return Icons.check_circle_outline_rounded;
  }
}
