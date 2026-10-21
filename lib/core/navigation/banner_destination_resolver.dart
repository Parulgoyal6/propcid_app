import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/banner_destination.dart';
import '../../providers/filter_provider.dart';
import '../constants/app_constants.dart';

/// The single place that decides where a `BannerDestination` goes. Widgets
/// that show banners never call `Navigator` themselves — they build a
/// `BannerDestination` and call [BannerDestinationResolver.navigate].
abstract final class BannerDestinationResolver {
  static Future<void> navigate(
    BuildContext context,
    BannerDestination destination,
  ) async {
    switch (destination.type) {
      case BannerDestinationType.property:
        final id = destination.propertyId;
        if (id == null) return;
        Navigator.pushNamed(
          context,
          AppConstants.propertyDetailScreen,
          arguments: {'propertyId': id},
        );
        return;

      case BannerDestinationType.externalUrl:
        final url = destination.url;
        if (url == null) return;
        await _launch(context, url);
        return;

      case BannerDestinationType.collection:
        _applyFiltersAndSearch(context, destination);
        return;

      case BannerDestinationType.project:
      case BannerDestinationType.builder:
        if (destination.hasFilterFields) {
          _applyFiltersAndSearch(context, destination);
        } else {
          _showComingSoon(
            context,
            destination.comingSoonLabel ?? 'Coming soon',
          );
        }
        return;
    }
  }

  /// Sets whichever filter fields the destination carries, then navigates —
  /// `SearchResultsScreen` re-runs `PropertyProvider.runSearch` itself from
  /// current `FilterProvider` state on its own `initState`, so setting the
  /// filters here (before it mounts) is all that's needed.
  static void _applyFiltersAndSearch(
    BuildContext context,
    BannerDestination destination,
  ) {
    final filters = context.read<FilterProvider>();
    if (destination.category != null) filters.setCategory(destination.category);
    if (destination.listingType != null) {
      filters.setListingType(destination.listingType);
    }
    if (destination.hashtag != null) filters.setHashtag(destination.hashtag);
    if (destination.city != null) filters.setCities([destination.city!]);
    if (destination.subtype != null) filters.setSubtype(destination.subtype);
    if (destination.budgetMin != null || destination.budgetMax != null) {
      filters.setBudgetRange(
        RangeValues(
          destination.budgetMin ?? AppConstants.priceMin,
          destination.budgetMax ?? AppConstants.priceMax,
        ),
      );
    }

    Navigator.pushNamed(context, AppConstants.searchResultsScreen);
  }

  static void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static Future<void> _launch(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showComingSoon(context, 'Could not open that link.');
      }
    } catch (_) {
      if (context.mounted) {
        _showComingSoon(context, 'Could not open that link.');
      }
    }
  }
}
