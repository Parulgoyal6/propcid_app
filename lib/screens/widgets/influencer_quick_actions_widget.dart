import 'package:flutter/material.dart';

import '../../config/launch_features.dart';
import '../../core/constants/app_constants.dart';

/// The influencer Content tab's "Quick Actions" grid.
///
/// Previously four tiles, two of which (`Campaigns`, `Earnings`) were
/// `() {}` — a visible button that silently did nothing — and a third
/// (`Analytics`) had no way to reach the dashboard's own Analytics tab
/// since this widget has no navigation context of its own. Now:
///   * Upload Video — unchanged, still opens the influencer video form.
///   * Analytics — calls back up to the dashboard to switch its own tab,
///     rather than pushing a route or duplicating that tab's content.
///   * Campaigns — Meta publishing is disabled for production
///     ([LaunchFeatures.metaPublishing]); the tile is hidden entirely
///     while it is, and only routes to the real Social Campaigns screen
///     once the flag is on. Never shown as a dead button.
///   * Earnings — removed outright: there is no portal-equivalent
///     destination for it, and a placeholder would be its own dead end.
class InfluencerQuickActionsWidget extends StatelessWidget {
  const InfluencerQuickActionsWidget({
    super.key,
    required this.onAnalyticsTap,
    @visibleForTesting bool? metaPublishingEnabled,
  }) : _metaPublishingEnabled = metaPublishingEnabled;

  /// Switches the parent dashboard to its own Analytics tab. A plain
  /// callback rather than a route push or a second dashboard instance —
  /// the real Analytics tab already exists one level up.
  final VoidCallback onAnalyticsTap;

  /// Overrides [LaunchFeatures.metaPublishing] for this instance. Null in
  /// every production call site (the compiled-in flag is used); tests pass
  /// `true` to verify the Campaigns tile's enabled behaviour without a
  /// separate `--dart-define` test run.
  final bool? _metaPublishingEnabled;

  Widget _action(IconData icon, String title, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _action(
        Icons.video_call_rounded,
        "Upload Video",
        Colors.red,
        () => Navigator.pushNamed(
          context,
          AppConstants.influencerVideoFormScreen,
        ),
      ),
      _action(
        Icons.analytics_rounded,
        "Analytics",
        Colors.blue,
        onAnalyticsTap,
      ),
      if (_metaPublishingEnabled ?? LaunchFeatures.metaPublishing)
        _action(
          Icons.campaign_rounded,
          "Campaigns",
          Colors.green,
          () =>
              Navigator.pushNamed(context, AppConstants.socialCampaignsScreen),
        ),
    ];

    // Two tiles per row. An odd tile out (Campaigns, when Meta publishing
    // is enabled) gets a transparent filler beside it rather than
    // stretching to double width or leaving a lopsided row.
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final hasSecond = i + 1 < tiles.length;
      rows.add(
        Row(
          children: [
            tiles[i],
            const SizedBox(width: 14),
            hasSecond ? tiles[i + 1] : const Expanded(child: SizedBox()),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          rows[i],
        ],
      ],
    );
  }
}
