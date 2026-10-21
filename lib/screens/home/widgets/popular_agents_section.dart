// screens/home/widgets/popular_agents_section.dart
//
// Home's "Popular Brokers" and "Popular Influencers" rails — the Flutter
// counterpart to the portal's "Top Brokers" / "Top Influencers" sections
// (`PublicHomePage.tsx`/`AuthenticatedHomePage.tsx`, `fetchProjects`'
// `agentsQuery` against `profiles`, split client-side by `user_type`).
//
// Both rails share one query shape (`PeopleSearchService.listPopularAgents`)
// and one card widget below — they differ only in which `UserProfile.isX`
// getter selects their rows and in their section title, so this file holds
// a private base rail rather than two near-duplicate widgets.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW
// ------------------------------------------
// Same convention as the other admin/backend-driven Home rails: nothing
// renders while loading, on failure, or when there are genuinely no matching
// approved profiles.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../models/user_profile.dart';
import '../../../services/people_search_service.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/verified_badge.dart';

/// Shared with [TopBuildersSection] — one card style for every profile rail
/// on Home, so a builder/broker/influencer card reads as the same kind of
/// thing wherever it appears.
/// Taller than the card itself — the rails' ListViews clip to their bounds,
/// so [AgentCard]'s outer margin reserves room for its raised 3D shadow.
const double kAgentRailHeight = 198;
const double kAgentCardWidth = 138;

const double _kAvatarSize = 60;
const double _kCardRadius = 20;

/// Layered "lifted" elevation: a solid warm lip right under the card (reads
/// as the card's extruded bottom edge), a wide soft orange glow, and a
/// tight dark contact shadow.
const List<BoxShadow> _kCard3dShadow = [
  BoxShadow(color: Color(0xFFFFE2CC), offset: Offset(0, 4)),
  BoxShadow(color: Color(0x33F97316), blurRadius: 18, offset: Offset(0, 10)),
  BoxShadow(color: Color(0x1F1A1A2E), blurRadius: 3, offset: Offset(0, 2)),
];

class PopularBrokersSection extends StatelessWidget {
  const PopularBrokersSection({super.key, this.service});

  @visibleForTesting
  final PeopleSearchService? service;

  @override
  Widget build(BuildContext context) {
    return _PopularAgentsRail(
      title: 'Popular Brokers',
      roleSelector: (p) => p.isBroker,
      service: service,
    );
  }
}

class PopularInfluencersSection extends StatelessWidget {
  const PopularInfluencersSection({super.key, this.service});

  @visibleForTesting
  final PeopleSearchService? service;

  @override
  Widget build(BuildContext context) {
    return _PopularAgentsRail(
      title: 'Popular Influencers',
      roleSelector: (p) => p.isInfluencer,
      service: service,
    );
  }
}

class _PopularAgentsRail extends StatefulWidget {
  const _PopularAgentsRail({
    required this.title,
    required this.roleSelector,
    this.service,
  });

  final String title;
  final bool Function(UserProfile) roleSelector;
  final PeopleSearchService? service;

  @override
  State<_PopularAgentsRail> createState() => _PopularAgentsRailState();
}

class _PopularAgentsRailState extends State<_PopularAgentsRail>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying popular agents every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<UserProfile>> _future =
      (widget.service ?? PeopleSearchService()).listPopularAgents();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<UserProfile>>(
      future: _future,
      builder: (context, snapshot) {
        // Was `return const SizedBox.shrink()` while waiting, same as the
        // empty/error case below — meaning this rail's real content simply
        // popped into existence with no transition once the query resolved.
        // A shimmer placeholder here (shown only for the actual in-flight
        // wait, never for a genuinely empty/failed result) removes that
        // pop-in without changing what's ultimately shown once loaded.
        if (snapshot.connectionState != ConnectionState.done) {
          return AgentRailShimmer(title: widget.title);
        }

        final all = snapshot.data;
        if (all == null) return const SizedBox.shrink();
        final agents = all.where(widget.roleSelector).toList();
        if (agents.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: widget.title),
              SizedBox(
                height: kAgentRailHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingL,
                  ),
                  itemCount: agents.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(
                      right: AppConstants.spacingM,
                    ),
                    child: ScaleTap(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppConstants.publicProfileScreen,
                        arguments: {'userId': agents[i].userId},
                      ),
                      child: AgentCard(agent: agents[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Loading placeholder for [_PopularAgentsRail] and [TopBuildersSection] —
/// same header + same rail height + the same [AgentCard] shape, shimmering.
class AgentRailShimmer extends StatelessWidget {
  const AgentRailShimmer({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          SizedBox(
            height: kAgentRailHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingL,
              ),
              itemCount: 4,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: AppConstants.spacingM),
                child: AgentCardShimmer(width: kAgentCardWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card used by every profile rail on Home (brokers, influencers,
/// builders) — avatar, name/company, city, then either a verified badge or
/// years of experience.
class AgentCard extends StatelessWidget {
  const AgentCard({super.key, required this.agent});

  final UserProfile agent;

  @override
  Widget build(BuildContext context) {
    final experience = agent.effectiveExperience;
    // Bounds decoding to the avatar's actual rendered pixels (64×64
    // logical) rather than the source's native resolution.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final avatarCachePx = (_kAvatarSize * dpr).round();

    return Container(
      width: kAgentCardWidth,
      // Keeps the raised shadow inside the rail's clipped bounds.
      margin: const EdgeInsets.only(top: 4, bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kCardRadius),
        // Faint top-to-bottom shading so the face reads as a lit surface.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFFFF8F2)],
        ),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: _kCard3dShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCardRadius - 1),
        child: Stack(
          children: [
            // Brand header band the avatar sits across.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 46,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFB923C), Color(0xFFFED7AA)],
                  ),
                ),
              ),
            ),
            // Soft glossy bubbles on the band for depth.
            Positioned(top: -18, right: -14, child: _bubble(56, 0.22)),
            Positioned(top: 18, left: -10, child: _bubble(26, 0.18)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingS,
                14,
                AppConstants.spacingS,
                12,
              ),
              child: Column(
                children: [
                  _raisedAvatar(agent, avatarCachePx),
                  const SizedBox(height: 8),
                  Text(
                    agent.displayTitle ?? 'PropCID Member',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (agent.effectiveCity != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            agent.effectiveCity!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Spacer(),
                  if (agent.isVerified)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppConstants.chipRadius),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x4010B981),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: VerifiedBadge(),
                    )
                  else if (experience != null && experience > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(
                          AppConstants.chipRadius,
                        ),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        '$experience yrs exp.',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Avatar lifted off the card: gradient ring, white gap, drop shadow.
  Widget _raisedAvatar(UserProfile agent, int cachePx) => Container(
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: AppColors.primaryGradient,
      boxShadow: const [
        BoxShadow(color: Color(0x40F97316), blurRadius: 12, offset: Offset(0, 6)),
      ],
    ),
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: agent.avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: agent.avatarUrl!,
                width: _kAvatarSize,
                height: _kAvatarSize,
                fit: BoxFit.cover,
                memCacheWidth: cachePx,
                memCacheHeight: cachePx,
                placeholder: (_, _) => _avatarFallback(agent),
                errorWidget: (_, _, _) => _avatarFallback(agent),
              )
            : _avatarFallback(agent),
      ),
    ),
  );

  Widget _bubble(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );

  Widget _avatarFallback(UserProfile agent) => Container(
    width: _kAvatarSize,
    height: _kAvatarSize,
    color: AppColors.primaryLight,
    alignment: Alignment.center,
    child: Text(
      agent.initials,
      style: AppTextStyles.heading3.copyWith(
        color: AppColors.primary,
        fontSize: 18,
      ),
    ),
  );
}
