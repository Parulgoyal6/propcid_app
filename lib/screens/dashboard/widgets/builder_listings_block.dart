// screens/dashboard/widgets/builder_listings_block.dart
//
// "My Listings" on the builder dashboard — heading, spacing and section
// together, so all three disappear as one when the builder has no listings.
//
// WHY THIS WRAPPER EXISTS
// -----------------------
// A builder publishes projects to `builder_projects`, never listings to
// `properties` — no portal builder surface creates one. So for almost every
// builder this section is permanently empty, and an empty section with a heading
// is worse than no section.
//
// It is not deleted, though: a builder may already have `properties` rows from
// before "Add Project" was pointed at the project wizard, and those must stay
// reachable. Hidden when empty, shown when not.
//
// Why a wrapper rather than a condition in the dashboard's `sections` list: the
// heading and the 22 dp gap above it are separate entries in that list, and
// `MyListingsSection` keeps its count private. Collapsing them individually
// would also reshape the list around an un-keyed `StatefulWidget`, which lets
// Flutter re-create its `State` — `initState` runs again, `_load()` fires again,
// the callback fires again, and the rebuild loops. One entry, one key, no
// reshape.
import 'package:flutter/material.dart';

import '../../../widgets/shared/app_surface_card.dart';
import '../my_listings_section.dart';

/// Gap above the heading. Lifted out of the dashboard's `sections` list so it
/// collapses with the block instead of leaving a hole behind it.
const double _kBlockTopGap = 22;

class BuilderListingsBlock extends StatefulWidget {
  const BuilderListingsBlock({
    super.key,
    required this.userId,
    this.sectionBuilder,
  });

  final String userId;

  /// Injected by tests so the collapse logic can be driven without a database.
  ///
  /// `MyListingsSection` builds its own `PropertyService` inside `_load()`, so
  /// there is no other way to hand it a count. Production always uses the real
  /// section below.
  @visibleForTesting
  final Widget Function(ValueChanged<int> onCountChanged)? sectionBuilder;

  @override
  State<BuilderListingsBlock> createState() => _BuilderListingsBlockState();
}

class _BuilderListingsBlockState extends State<BuilderListingsBlock> {
  /// How many listings the section holds. **Null means "not known yet"** — the
  /// load has not finished, or it failed.
  ///
  /// Only an actual zero hides the block. Treating null as zero would flash the
  /// section away and back on every open, and treating a failure as zero would
  /// hide `MyListingsSection`'s own error state and its Retry with it.
  int? _count;

  void _onCountChanged(int count) {
    if (!mounted || count == _count) return;
    setState(() => _count = count);
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _kBlockTopGap),
        const DashboardSectionLabel('My Listings'),
        const SizedBox(height: 10),
        widget.sectionBuilder?.call(_onCountChanged) ??
            MyListingsSection(
              // Keyed so the element survives this block rebuilding when the
              // count arrives. Without it the section can be re-created
              // mid-load and re-fetch — see the header note.
              key: const ValueKey('builder-my-listings'),
              userId: widget.userId,
              onCountChanged: _onCountChanged,
            ),
      ],
    );
  }
}
