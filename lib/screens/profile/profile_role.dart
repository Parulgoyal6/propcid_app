import 'package:flutter/material.dart';

/// Role display helpers, ported verbatim from `_ProfileScreenState`'s
/// `_roleColor` / `_roleLabel` so the rebuilt Profile screen and its section
/// widgets share one definition instead of each re-deriving it — see
/// blueprint §16.4.
///
/// Behaviour is unchanged, including the `Member` fallback for individual and
/// unrecognised user types.
Color roleColor(String? userType) {
  switch (userType?.toLowerCase()) {
    case 'builder':
      return const Color(0xFF3B82F6);
    case 'broker':
      return Colors.teal;
    case 'influencer':
      // Same pink already used for the "Influencers" category tile
      // (category_icon_grid.dart), so the badge colour matches everywhere.
      return const Color(0xFFDB2777);
    default:
      return Colors.grey;
  }
}

String roleLabel(String? userType) {
  switch (userType?.toLowerCase()) {
    case 'builder':
      return 'Builder';
    case 'broker':
      return 'Broker';
    case 'influencer':
      return 'Influencer';
    default:
      return 'Member';
  }
}
