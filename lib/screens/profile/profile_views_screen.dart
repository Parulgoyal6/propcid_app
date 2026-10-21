// screens/profile/profile_views_screen.dart
//
// "Who viewed my profile" — a port of pages/ProfileViews.tsx.
//
// The header deliberately shows two numbers. `profile_views` holds one row per
// (owner, viewer) pair, so the headline counts PEOPLE and never moves when someone
// returns; total visits sits beside it so the smaller number does not look broken.
// The portal makes the same distinction for the same reason.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/number_format.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/scale_tap.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_views_provider.dart';
import '../../services/profile_view_service.dart';
import '../../widgets/shared/app_surface_card.dart';
import 'public_profile_role.dart';
import 'widgets/public_profile_stats.dart';

class ProfileViewsScreen extends StatelessWidget {
  const ProfileViewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileViewsProvider(),
      child: const _ProfileViewsView(),
    );
  }
}

class _ProfileViewsView extends StatefulWidget {
  const _ProfileViewsView();

  @override
  State<_ProfileViewsView> createState() => _ProfileViewsViewState();
}

class _ProfileViewsViewState extends State<_ProfileViewsView> {
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || userId == _loadedFor) return;
    _loadedFor = userId;

    final provider = context.read<ProfileViewsProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId);
    });
  }

  void _openViewer(ProfileViewer viewer) {
    if (viewer.viewerId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': viewer.viewerId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileViewsProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile views',
          style: AppTextStyles.heading3.copyWith(fontSize: 16),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(
            color: AppColors.hairline,
            child: SizedBox(height: 1),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: provider.refresh,
        child: provider.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.all(AppConstants.spacingL),
                children: [
                  _SummaryCard(provider: provider),
                  const SizedBox(height: AppConstants.spacingL),
                  if (provider.viewers.isEmpty)
                    const EmptyStateView(
                      icon: Icons.visibility_outlined,
                      title: 'No profile views yet',
                      message:
                          'When someone opens your profile, they will appear here.',
                    )
                  else
                    for (final viewer in provider.viewers) ...[
                      _ViewerRow(
                        viewer: viewer,
                        onTap: () => _openViewer(viewer),
                      ),
                      const SizedBox(height: AppConstants.spacingM),
                    ],
                ],
              ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ProfileViewsProvider provider;

  const _SummaryCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            ),
            child: const Icon(
              Icons.visibility_outlined,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppConstants.spacingL),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCompactCount(provider.uniqueViewers),
                  style: AppTextStyles.heading2.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                const DashboardSectionLabel('Unique viewers'),
              ],
            ),
          ),
          // Only when the two numbers differ — otherwise it reads as a duplicate.
          if (provider.hasRepeatVisitors)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCompactCount(provider.totalVisits),
                  style: AppTextStyles.heading3.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                const DashboardSectionLabel('Total visits'),
              ],
            ),
        ],
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  final ProfileViewer viewer;
  final VoidCallback onTap;

  const _ViewerRow({required this.viewer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final profile = viewer.profile;
    final role = profile?.userType;
    final tint = roleColor(role);

    return Semantics(
      button: true,
      label: '${viewer.displayName}, viewed ${viewer.viewCount} times',
      child: ExcludeSemantics(
        child: ScaleTap(
          onTap: onTap,
          child: DashboardCard(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            child: Row(
              children: [
                _ViewerAvatar(viewer: viewer),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              viewer.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (role != null && role.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tint.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.pillRadius,
                                ),
                              ),
                              child: Text(
                                roleLabel(role),
                                style: AppTextStyles.chip.copyWith(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: tint,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (viewer.lastViewedAt != null)
                            Text(
                              profileRelativeTime(viewer.lastViewedAt!),
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 11.5,
                              ),
                            ),
                          if (viewer.isRepeatVisitor) ...[
                            const SizedBox(width: AppConstants.spacingS),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(
                                  AppConstants.pillRadius,
                                ),
                              ),
                              child: Text(
                                'Viewed ${viewer.viewCount} times',
                                style: AppTextStyles.chip.copyWith(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerAvatar extends StatelessWidget {
  final ProfileViewer viewer;

  const _ViewerAvatar({required this.viewer});

  static const double _size = 42;

  @override
  Widget build(BuildContext context) {
    final url = viewer.profile?.avatarUrl;
    final fallback = Center(
      child: Text(
        viewer.profile?.initials ?? 'U',
        style: AppTextStyles.caption.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: _size,
                height: _size,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
