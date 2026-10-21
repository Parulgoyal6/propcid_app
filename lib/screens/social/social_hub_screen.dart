import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/manage_list_tile.dart';
import '../../widgets/shared/section_header_back_button.dart';

/// Social — the entry point for Meta publishing.
///
/// Design: the `isSocial` screen, a header above six navigation cards.
///
/// Functionally this is the index over React's `features/social/*` panels
/// (`SocialAccountsPanel`, `CampaignsPanel`, `SocialPreferencesForm`,
/// `SocialActivityPanel`, `SocialAnalyticsPanel`) plus its lead-ad
/// submissions view. Each panel is its own workstream; this phase delivers the
/// hub and honest placeholders behind every card.
///
/// No provider and no queries: every card's destination owns its own data, and
/// the hub itself has nothing to load. Connecting a Facebook Page needs the
/// Meta OAuth mobile strategy, which is still an open decision — nothing here
/// pretends an account is connected.
class SocialHubScreen extends StatelessWidget {
  const SocialHubScreen({super.key});

  static const List<_SocialDestination> _destinations = [
    _SocialDestination(
      icon: Icons.facebook,
      label: 'Social Accounts',
      subtitle: 'Facebook & Instagram connection',
      route: AppConstants.socialAccountsScreen,
    ),
    _SocialDestination(
      icon: Icons.campaign_outlined,
      label: 'Social Campaigns',
      subtitle: 'Boost listings on Meta',
      route: AppConstants.socialCampaignsScreen,
    ),
    _SocialDestination(
      icon: Icons.people_outline,
      label: 'Social Leads',
      subtitle: 'Submissions from your lead ads',
      route: AppConstants.socialLeadsScreen,
    ),
    _SocialDestination(
      icon: Icons.settings_outlined,
      label: 'Social Preferences',
      subtitle: 'Auto-share & publishing defaults',
      route: AppConstants.socialPreferencesScreen,
    ),
    _SocialDestination(
      icon: Icons.schedule,
      label: 'Social Activity',
      subtitle: 'Publishing timeline',
      route: AppConstants.socialActivityScreen,
    ),
    _SocialDestination(
      icon: Icons.grid_view_rounded,
      label: 'Social Analytics',
      subtitle: 'Reach & post performance',
      route: AppConstants.socialAnalyticsScreen,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardHeaderBar(
                title: 'Social',
                subtitle: 'Connect Facebook & Instagram, publish everywhere',
              ),
              const SizedBox(height: 20),
              ManageListTile.group([
                for (final destination in _destinations)
                  ManageListTile(
                    icon: destination.icon,
                    label: destination.label,
                    subtitle: destination.subtitle,
                    onTap: () =>
                        Navigator.of(context).pushNamed(destination.route),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialDestination {
  final IconData icon;
  final String label;
  final String subtitle;

  /// Named route for the leaf screen, registered in `app.dart`.
  final String route;

  const _SocialDestination({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.route,
  });
}
