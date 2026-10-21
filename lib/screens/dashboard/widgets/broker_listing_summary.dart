// screens/dashboard/widgets/broker_listing_summary.dart
//
// The three summary cards above the portal's broker listing table
// (`BrokerContentManager.tsx:235-280`): Total, Active, Sold.
//
// PRESENTATION ONLY
// -----------------
// Folded from the `PropertyModel` list the Broker dashboard already loaded through
// `PropertyService.getPropertiesByUser` for the Spec I sections. No query, no
// service change.
//
// The portal renders three equal cards in a row plus a table below with columns
// Property | Location | Price | Status | Actions. Those five columns are already
// covered per-card by `MyListingsSection` — cover, title, price, location, status
// picker and the three actions — so only the summary strip was missing.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/property_model.dart';

class BrokerListingSummary extends StatelessWidget {
  const BrokerListingSummary({super.key, required this.properties});

  final List<PropertyModel> properties;

  int _withStatus(String status) =>
      properties.where((p) => p.status == status).length;

  @override
  Widget build(BuildContext context) {
    // The list below shows its own spinner and its own empty state; a summary of
    // nothing would be three zeros above them.
    if (properties.isEmpty) return const SizedBox.shrink();

    final tiles = <_Tile>[
      _Tile('Total', '${properties.length}', AppColors.primary),
      _Tile('Active', '${_withStatus('active')}', AppColors.success),
      _Tile('Sold', '${_withStatus('sold')}', AppColors.statusBooked),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tiles[i].tint.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: tiles[i].tint.withValues(alpha: 0.14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tiles[i].value,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tiles[i].tint,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tiles[i].label,
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile {
  const _Tile(this.label, this.value, this.tint);

  final String label;
  final String value;
  final Color tint;
}
