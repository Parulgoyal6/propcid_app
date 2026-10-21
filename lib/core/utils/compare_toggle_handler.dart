import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/compare_provider.dart';
import '../theme/app_colors.dart';

/// Single choke point every property card's compare toggle calls through —
/// so the sign-in / "limit reached" / "category mismatch" feedback is worded
/// and triggered identically everywhere, instead of each of the ~8 call sites
/// (Home rails, Search, Shortlist, My Activity, Property Detail) re-deriving
/// it from [CompareProvider.toggle]'s return value.
///
/// Portal parity (`PropertyCard.tsx`'s compare handler): comparing requires
/// being signed in, and each failure is a two-line toast — a title plus a
/// description — with the portal's exact copy.
void handleCompareToggle(BuildContext context, PropertyModel property) {
  if (!context.read<AuthProvider>().isLoggedIn) {
    _toast(
      context,
      'Login Required',
      'Please login to compare properties',
      isError: false,
    );
    return;
  }

  final compare = context.read<CompareProvider>();
  final result = compare.toggle(property);

  switch (result) {
    case CompareAddResult.added || CompareAddResult.removed:
      return;
    case CompareAddResult.limitReached:
      _toast(
        context,
        'Compare limit reached',
        'You can compare up to ${CompareProvider.maxCompare} properties. '
            'Remove one to compare another.',
      );
    case CompareAddResult.categoryMismatch:
      _toast(
        context,
        "Can't compare these",
        'You can only compare properties of the same category and listing '
            'type.',
      );
  }
}

void _toast(
  BuildContext context,
  String title,
  String description, {
  bool isError = true,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: isError ? AppColors.error : AppColors.textPrimary,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(description),
        ],
      ),
    ),
  );
}
