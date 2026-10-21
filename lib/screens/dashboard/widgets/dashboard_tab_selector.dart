import 'package:flutter/material.dart';

import '../../../core/widgets/segmented_tab_pill.dart';

/// The three dashboard tabs, in display order.
enum DashboardTab { analytics, content, audience }

/// Analytics / Content Manager / Audience selector.
///
/// A thin wrapper around the shared [SegmentedTabPill] — no second pill
/// implementation.
///
/// The middle tab reads "Content Manager" for every role. Earlier this was
/// role-specific ("Listings" / "Projects" / "Content"); the approved design
/// shows one label across all roles, wrapping onto a second line, so it wins.
class DashboardTabSelector extends StatelessWidget {
  final DashboardTab selected;
  final ValueChanged<DashboardTab> onChanged;

  const DashboardTabSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedTabPill(
      labels: const ['Analytics', 'Content Manager', 'Audience'],
      selectedIndex: DashboardTab.values.indexOf(selected),
      onChanged: (i) => onChanged(DashboardTab.values[i]),
      // "Content Manager" runs onto two lines at this width in the design.
      maxLines: 2,
    );
  }
}
