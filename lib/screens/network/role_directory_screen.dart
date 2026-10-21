// screens/network/role_directory_screen.dart
//
// Public "browse all" directory for one profile role — Verified Brokers,
// Builders, or Influencers. Destination for the matching Home "Popular
// Categories" tile (`category_icon_grid.dart`), mirroring the portal's
// BrokersList.tsx / BuildersList.tsx / InfluencersList.tsx: one query
// against `profiles` (approved, not blocked, matching `user_type`), a
// client-side name/company/city filter, and a card grid — no pagination,
// matching the portal's own simplicity (all three of its pages fetch the
// full result set in one shot too).
//
// The card (`_DirectoryCard`) is local to this screen, not the shared
// [AgentCard] `popular_agents_section.dart`'s Home rails use — this screen's
// reference design wants a richer card (subtitle, location, experience row,
// a "View Profile" button) than that compact rail card carries, and
// widening `AgentCard` itself would have changed those Home rails too.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/animations/fade_slide_in.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/user_profile.dart';
import '../../services/people_search_service.dart';
import '../profile/public_profile_role.dart' show roleSubtitle;

class RoleDirectoryScreen extends StatefulWidget {
  const RoleDirectoryScreen({
    super.key,
    required this.userType,
    required this.title,
    this.loader,
  });

  /// `profiles.user_type` this directory lists — `'broker'`, `'builder'`,
  /// or `'influencer'`.
  final String userType;

  final String title;

  /// Overrides the live Supabase query in tests. Production always uses
  /// [_load]'s real one.
  @visibleForTesting
  final Future<List<UserProfile>> Function()? loader;

  @override
  State<RoleDirectoryScreen> createState() => _RoleDirectoryScreenState();
}

class _RoleDirectoryScreenState extends State<RoleDirectoryScreen> {
  final TextEditingController _search = TextEditingController();
  late Future<List<UserProfile>> _future = _load();
  String _query = '';

  /// Profile ids that have already played their entrance animation.
  final Set<String> _entered = <String>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<UserProfile>> _load() {
    return widget.loader?.call() ?? _loadFromSupabase();
  }

  Future<List<UserProfile>> _loadFromSupabase() async {
    final rows = await Supabase.instance.client
        .from('profiles')
        .select(PeopleSearchService.columns)
        .eq('user_type', widget.userType)
        .eq('approval_status', 'approved')
        .not('is_blocked', 'is', true)
        .order('display_name', ascending: true)
        .limit(200);

    return List<Map<String, dynamic>>.from(
      rows,
    ).map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row))).where(
      (profile) => profile.userId.isNotEmpty,
    ).toList(growable: false);
  }

  List<UserProfile> _filtered(List<UserProfile> all) {
    if (_query.isEmpty) return all;
    return all.where((profile) {
      final name = (profile.displayName ?? '').toLowerCase();
      final company = (profile.companyName ?? '').toLowerCase();
      final city = (profile.effectiveCity ?? '').toLowerCase();
      return name.contains(_query) ||
          company.contains(_query) ||
          city.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading2.copyWith(fontSize: 15.5),
                  ),
                  Text(
                    'Trusted professionals. All verified.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        // No filter action: the search field below is this screen's only
        // working filter, so a non-functional filter icon was removed.
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name, company or city',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.cardBackground,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppConstants.searchBarRadius,
                  ),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<UserProfile>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return EmptyStateView(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load this list",
                    message: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: () => setState(() => _future = _load()),
                  );
                }

                final results = _filtered(snapshot.data ?? const []);
                if (results.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.person_search_rounded,
                    title: 'No matches',
                    message: _query.isEmpty
                        ? '${widget.title} will appear here once approved.'
                        : 'Try a different name, company or city.',
                  );
                }

                // A fixed column count with an explicit row height, not
                // `SliverGridDelegateWithMaxCrossAxisExtent` +
                // `childAspectRatio` — that combination lets the actual
                // per-column width end up NARROWER than `kAgentCardWidth`
                // whenever the screen width doesn't divide evenly into
                // `maxCrossAxisExtent`-sized columns (its `crossAxisCount`
                // is a `.ceil()`, so it always tries to fit one more column
                // than fits cleanly). Since `childAspectRatio` derives cell
                // *height* from that same possibly-shrunken width, the row
                // height shrank right along with it — while `AgentCard`'s
                // own content (a 64dp avatar plus two lines of text plus a
                // badge) doesn't shrink to match, so it overflowed the now
                // too-short cell by a small, fixed amount on most real
                // phone widths. `mainAxisExtent` fixes the row height
                // directly, independent of however many columns fit.
                final gridWidth = MediaQuery.of(context).size.width - 32;
                final crossAxisCount = (gridWidth / (_kCardWidth + 14))
                    .floor()
                    .clamp(2, 6);

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: _kCardExtent,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final agent = results[index];
                    // Entrance plays once per profile (not on scroll-back).
                    return FadeSlideIn(
                      animate: _entered.add(agent.userId),
                      index: index < 8 ? index : 0,
                      child: _DirectoryCard(
                        agent: agent,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.publicProfileScreen,
                          arguments: {'userId': agent.userId},
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Card width/height for the directory grid — wider and taller than the
/// shared `AgentCard`/`kAgentRailHeight` (Home's rail card) to fit this
/// screen's richer details (subtitle, location, experience, "View Profile").
const double _kCardWidth = 158;
const double _kCardExtent = 228;

/// Layered elevation for the directory card: a soft, wide orange-tinted glow
/// plus a tight, darker contact shadow — together they read as a card lifted
/// off the page rather than a flat tile.
const List<BoxShadow> _kCardShadow = [
  BoxShadow(color: Color(0x24F97316), blurRadius: 22, offset: Offset(0, 10)),
  BoxShadow(color: Color(0x141A1A2E), blurRadius: 4, offset: Offset(0, 2)),
];

/// The directory grid's card — centered avatar with a verified tick, name,
/// company/role subtitle, location, years of experience, and a "View
/// Profile" button pinned to the bottom. Local to this screen (see the
/// file-level doc comment for why it isn't the shared `AgentCard`).
///
/// Every detail row always occupies the same slot (a missing city or
/// experience leaves an empty line rather than collapsing) and the button
/// sits below a [Spacer], so all cards in a grid row line up regardless of
/// which optional details each profile has.
class _DirectoryCard extends StatefulWidget {
  const _DirectoryCard({required this.agent, required this.onTap});

  final UserProfile agent;
  final VoidCallback onTap;

  @override
  State<_DirectoryCard> createState() => _DirectoryCardState();
}

class _DirectoryCardState extends State<_DirectoryCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final subtitle = agent.companyName?.trim().isNotEmpty == true
        ? agent.companyName!.trim()
        : (agent.agencyName?.trim().isNotEmpty == true
              ? agent.agencyName!.trim()
              : roleSubtitle(agent.userType));
    final city = agent.effectiveCity;
    final experience = agent.effectiveExperience;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF4EB), Colors.white],
              stops: [0, 0.45],
            ),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: _kCardShadow,
          ),
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Column(
            children: [
              _DirectoryAvatar(agent: agent),
              const SizedBox(height: 10),
              Text(
                agent.displayTitle ?? 'PropCID Member',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(fontSize: 10.5),
              ),
              const SizedBox(height: 8),
              _DetailLine(icon: Icons.location_on_rounded, text: city),
              const SizedBox(height: 3),
              _DetailLine(
                icon: Icons.work_outline_rounded,
                text: experience != null && experience > 0
                    ? '$experience+ Years Exp.'
                    : null,
              ),
              const Spacer(),
              _ViewProfileButton(onTap: widget.onTap),
            ],
          ),
        ),
      ),
    );
  }
}

/// One centered icon + text detail row. A null [text] still reserves the
/// row's height so neighbouring cards stay aligned.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final value = text;
    return SizedBox(
      height: 14,
      child: value == null
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 11, color: AppColors.primary),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 10),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Solid gradient "View Profile" pill with a raised shadow.
class _ViewProfileButton extends StatelessWidget {
  const _ViewProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppConstants.buttonRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          colors: [Color(0xFFFB923C), AppColors.primary],
        ),
        boxShadow: AppColors.primaryActionShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: double.infinity,
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'View Profile',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar with a gradient ring and, for verified profiles, a tick badge on
/// the ring's lower-right edge — inside the avatar's own bounds, so it can
/// never overlap the name (the old side ribbon covered it).
class _DirectoryAvatar extends StatelessWidget {
  const _DirectoryAvatar({required this.agent});

  final UserProfile agent;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        agent.initials,
        style: AppTextStyles.heading3.copyWith(
          color: AppColors.primary,
          fontSize: 20,
        ),
      ),
    );

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          Container(
            width: _size,
            height: _size,
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFDBA74), AppColors.primary],
              ),
              boxShadow: AppColors.primaryActionShadow,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: agent.avatarUrl != null
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: agent.avatarUrl!,
                          width: _size,
                          height: _size,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => fallback,
                          errorWidget: (_, _, _) => fallback,
                        ),
                      )
                    : fallback,
              ),
            ),
          ),
          if (agent.isVerified)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
