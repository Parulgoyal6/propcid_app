import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/dashboard_analytics_provider.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/individual_dashboard_provider.dart';
import '../../services/property_service.dart';
import '../post_property/post_property_screen.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/shared/section_header_back_button.dart';
import 'widgets/broker_leads_section.dart';
import 'widgets/broker_visit_bookings_section.dart';
import 'widgets/outgoing_site_visits_section.dart';
import 'widgets/dashboard_primitives.dart';
import 'widgets/dashboard_tab_bodies.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import '../../widgets/shared/stat_kpi_card.dart';

class _BrandGradient {
  // c1 and the hero gradient were removed in Phase 3 with the bespoke
  // gradient header; DashboardHeaderBar replaced it. c2/c4 were the old
  // indigo/violet brand pair — now PropCid's orange, matching AppColors.
  static const Color c2 = AppColors.primary;
  static const Color c4 = Color(0xFFC2410C);
}

/// The Individual dashboard's five sections.
///
/// `IndividualDashboardManage.tsx` — Analytics · Content · Leads · Visits ·
/// Audience: the same Leads/Visits pair every other role's manage dashboard
/// already has (`property_inquiries`/`property_visit_bookings`, scoped to
/// this person's own listings exactly like Broker's — neither table has a
/// role column, so "my properties" already is the correct scope regardless
/// of user type).
///
/// Its own enum, like Broker/Builder/Influencer, so the shared
/// `DashboardTab`/`DashboardTabSelector` (which has no room for a fourth or
/// fifth tab) is left untouched — nothing else still uses it for rendering.
enum IndividualSection { analytics, content, leads, visits, audience }

/// Five labels over the app's existing segmented pill.
class IndividualSectionSelector extends StatelessWidget {
  const IndividualSectionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final IndividualSection selected;
  final ValueChanged<IndividualSection> onChanged;

  static const _labels = <IndividualSection, String>{
    IndividualSection.analytics: 'Analytics',
    // Preserved verbatim from the shared DashboardTabSelector this replaces
    // — not shortened to "Content" like Broker/Influencer's own tabs, so
    // this doesn't change what a returning Individual user already sees.
    IndividualSection.content: 'Content Manager',
    IndividualSection.leads: 'Leads',
    IndividualSection.visits: 'Visits',
    IndividualSection.audience: 'Audience',
  };

  @override
  Widget build(BuildContext context) {
    return SegmentedTabPill(
      labels: IndividualSection.values.map((s) => _labels[s]!).toList(),
      selectedIndex: IndividualSection.values.indexOf(selected),
      onChanged: (i) => onChanged(IndividualSection.values[i]),
      labelFontSize: 11,
      // "Content Manager" wraps at this width, same as the selector this
      // replaces.
      maxLines: 2,
    );
  }
}

// Entry point — provides the provider and delegates to the stateful view.
class IndividualDashboardScreen extends StatelessWidget {
  const IndividualDashboardScreen({super.key, this.initialSection});

  /// A `DashboardSection` value (`'leads'`/`'visits'`) to open on, from
  /// `ManageDashboardDispatcher`. Anything else, including `null`, keeps the
  /// ordinary Analytics default.
  final String? initialSection;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Existing provider and business logic, untouched.
        ChangeNotifierProvider(create: (_) => IndividualDashboardProvider()),
        // Additive: the metrics the approved design shows, ported from the
        // React portal's IndividualAnalytics.tsx / IndividualAudienceInsights.
        ChangeNotifierProvider(
          create: (_) => DashboardAnalyticsProvider(
            // IndividualAnalytics.tsx reads `influencer_videos`, but
            // IndividualAudienceInsights.tsx reads `properties` and documents
            // why: "individual users' content = their property listings,
            // matching the broker variant; there is no 'posts' table". The two
            // React files disagree; the documented one is followed for both
            // tabs so the screen reflects the listings a user actually owns.
            analyticsSource: AnalyticsContentSource.properties,
            audienceSource: AnalyticsContentSource.properties,
            // Only the Individual variant queries `saved_properties`.
            includeSavedProperties: true,
          ),
        ),
      ],
      child: _IndividualDashboardView(initialSection: initialSection),
    );
  }
}

// ── Stateful view ─────────────────────────────────────────────────────────────

class _IndividualDashboardView extends StatefulWidget {
  const _IndividualDashboardView({this.initialSection});

  final String? initialSection;

  @override
  State<_IndividualDashboardView> createState() =>
      _IndividualDashboardViewState();
}

class _IndividualDashboardViewState extends State<_IndividualDashboardView> {
  /// Opens on Analytics — unless `widget.initialSection` names one of this
  /// dashboard's own sections (e.g. `'leads'`/`'visits'`); unrecognised
  /// values (including `null`, every existing caller's default) fall back to
  /// Analytics exactly as before.
  late IndividualSection _tab = IndividualSection.values.firstWhere(
    (s) => s.name == widget.initialSection,
    orElse: () => IndividualSection.analytics,
  );
  String? _loadedUserId;

  @override
  void initState() {
    super.initState();
    // Load after the first frame so BuildContext is fully wired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().userId;
      if (userId != null) {
        context.read<IndividualDashboardProvider>().loadProperties(userId);
        // Deferred with the rest: load() notifies synchronously before its
        // first await, which would mark this element dirty mid-build.
        if (userId != _loadedUserId) {
          _loadedUserId = userId;
          context.read<DashboardAnalyticsProvider>().load(userId);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IndividualDashboardProvider>();

    // ── Computed stats ────────────────────────────────────────────────────────
    final props = provider.myProperties;
    final listings = props.length;
    final active = props.where((p) => p.status == 'active').length;
    final views = props.fold<int>(0, (sum, p) => sum + (p.views ?? 0));
    const inquiries = 0; // placeholder until inquiry feature exists

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Design places an icon-only square FAB on the Content tab only. Its
      // action is the same PostPropertyScreen push `_CreatePropertyButton`
      // already performs — reachable two ways on that tab, as in the design.
      floatingActionButton: _tab == IndividualSection.content
          // Design insets the FAB 20 dp from the right edge; Scaffold's
          // endFloat location defaults to 16.
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DashboardCreateFab(
                semanticLabel: 'Create property',
                onPressed: _onCreateProperty,
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        color: _BrandGradient.c2,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DashboardHeaderBar(
                        title: 'Manage Dashboard',
                        subtitle: 'Manage your content and track performance',
                      ),
                      const SizedBox(height: 18),
                      IndividualSectionSelector(
                        selected: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: _buildTabBody(
                  context,
                  provider,
                  listings: listings,
                  active: active,
                  views: views,
                  inquiries: inquiries,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }

  /// The create action this role already exposed, unchanged.
  void _onCreateProperty() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PostPropertyScreen()),
    );
  }

  Widget _buildTabBody(
    BuildContext context,
    IndividualDashboardProvider provider, {
    required int listings,
    required int active,
    required int views,
    required int inquiries,
  }) {
    final analytics = context.watch<DashboardAnalyticsProvider>();

    switch (_tab) {
      case IndividualSection.analytics:
        return DashboardAnalyticsBody(
          analytics: analytics.analytics,
          loading: analytics.analyticsLoading,
          failed: analytics.analyticsFailed,
          onRetry: analytics.refresh,
          // Read off the provider rather than hard-coded, so the flag that
          // decides whether `saved_properties` is queried is the same one that
          // decides whether the tile appears. They cannot drift apart.
          showSavedProperties: analytics.includeSavedProperties,
        );

      case IndividualSection.content:
        return DashboardContentBody(
          createLabel: 'Add Property',
          emptyActionLabel: 'Add Your First Property',
          onCreate: _onCreateProperty,
          sections: [
            // The role's own listing counts, preserved from
            // IndividualDashboardProvider.
            const DashboardSectionLabel('Overview'),
            const SizedBox(height: 10),
            _StatsGrid(
              listings: listings,
              active: active,
              views: views,
              inquiries: inquiries,
            ),
            const SizedBox(height: 22),
            const DashboardSectionLabel('My Properties'),
            const SizedBox(height: 10),
            // The design shows a single create CTA in the Content Library
            // header; that plus the FAB already cover this action, so the old
            // full-width gradient button would be a third duplicate.
            _buildPropertySection(context, provider),
          ],
        );

      // ── Leads — same `property_inquiries` + `property_visit_bookings`
      // unification Broker's own Leads tab already uses, scoped to this
      // person's own properties via IndividualDashboardProvider (already
      // loaded for the Content tab above — no second fetch).
      //
      // `BrokerVisitBookingsSection` is additionally mounted below the
      // unified list, unchanged itself: it is the only place in the app
      // with the full confirm/reschedule (date+time+status) edit sheet for
      // an incoming booking, and it must stay reachable from Leads now that
      // Visits no longer shows incoming data at all.
      case IndividualSection.leads:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Leads'),
            const SizedBox(height: 10),
            BrokerLeadsSection(properties: provider.myProperties),
            const SizedBox(height: AppConstants.spacingL),
            const DashboardSectionLabel('Manage Visit Bookings'),
            const SizedBox(height: 10),
            BrokerVisitBookingsSection(properties: provider.myProperties),
          ],
        );

      // ── Visits — requests THIS person made on OTHER people's listings ───
      //
      // Was `BrokerVisitBookingsSection` fed this person's own properties,
      // i.e. the identical incoming data Leads already showed (the root bug
      // this fix addresses) — replaced with the dashboard-shared outgoing
      // widget, backed by the existing `my-visit-requests` endpoint rather
      // than any locally-known property id list.
      case IndividualSection.visits:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardSectionLabel('Visit Bookings'),
            SizedBox(height: 10),
            OutgoingSiteVisitsSection(),
          ],
        );

      case IndividualSection.audience:
        return DashboardAudienceBody(
          audience: analytics.audience,
          loading: analytics.audienceLoading,
          failed: analytics.audienceFailed,
          onRetry: analytics.refresh,
        );
    }
  }

  Widget _buildPropertySection(
    BuildContext context,
    IndividualDashboardProvider provider,
  ) {
    if (provider.loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(color: _BrandGradient.c2),
        ),
      );
    }

    if (provider.myProperties.isEmpty) {
      return const _EmptyPropertiesState();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: provider.myProperties.length,
      itemBuilder: (_, index) {
        final property = provider.myProperties[index];
        return _PropertyCard(
          property: property,
          onEdit: () => _openEditScreen(property),
          onDelete: () => _showDeleteDialog(property),
        );
      },
    );
  }

  Future<void> _openEditScreen(PropertyModel property) async {
    final String id = property.id;

    PropertyEditBundle bundle;
    try {
      bundle = await PropertyService().fetchForEdit(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load property for editing: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (!mounted) return;
    final refreshNeeded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PostPropertyScreen(editPropertyId: id, editBundle: bundle),
      ),
    );

    if (refreshNeeded == true && mounted) {
      context.read<IndividualDashboardProvider>().refresh();
    }
  }

  Future<void> _showDeleteDialog(PropertyModel property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text(
          'Are you sure you want to delete this property? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<IndividualDashboardProvider>();
    try {
      await provider.deleteProperty(property.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Property deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}

// ── Section Title ─────────────────────────────────────────────────────────────

// ── Stats Grid (2×2, real values) ────────────────────────────────────────────

/// Re-skinned in Phase 3 to render the shared [MetricCard] so this dashboard
/// matches the other three roles (blueprint §16.5). Values, labels, icons,
/// accent colours and ordering are unchanged; the previous local
/// (and its entrance animation) is superseded by the shared card.
class _StatsGrid extends StatelessWidget {
  final int listings;
  final int active;
  final int views;
  final int inquiries;

  const _StatsGrid({
    required this.listings,
    required this.active,
    required this.views,
    required this.inquiries,
  });

  @override
  Widget build(BuildContext context) {
    return MetricCardGrid(
      cards: [
        MetricCard(
          label: 'Listings',
          value: '$listings',
          icon: Icons.home_rounded,
          accent: _BrandGradient.c2,
        ),
        MetricCard(
          label: 'Active',
          value: '$active',
          icon: Icons.trending_up_rounded,
          accent: Colors.teal,
        ),
        MetricCard(
          label: 'Views',
          value: '$views',
          icon: Icons.visibility_rounded,
          accent: Colors.blue,
        ),
        MetricCard(
          label: 'Inquiries',
          value: '$inquiries',
          icon: Icons.mail_rounded,
          accent: Colors.deepOrange,
        ),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyPropertiesState extends StatelessWidget {
  const _EmptyPropertiesState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _BrandGradient.c2.withOpacity(0.12),
                  _BrandGradient.c4.withOpacity(0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.home_work_outlined,
              size: 32,
              color: _BrandGradient.c2.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "You haven't posted any properties yet.",
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1C1530),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Create Property" above to post your first listing.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inline Property Card ──────────────────────────────────────────────────────

class _PropertyCard extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PropertyCard({required this.property, this.onEdit, this.onDelete});

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _statusColor(String? status) => switch (status) {
    'active' => Colors.green,
    'sold' => Colors.blue,
    'inactive' => Colors.grey,
    _ => Colors.amber,
  };

  String _statusLabel(String? status) => switch (status) {
    'active' => 'Active',
    'sold' => 'Sold',
    'inactive' => 'Inactive',
    _ => 'Pending',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final coverUrl = property.resolvedImageUrls.isNotEmpty
        ? property.resolvedImageUrls.first
        : null;
    final statusColor = _statusColor(property.status);
    final statusLabel = _statusLabel(property.status);
    final category = (property.category ?? 'Property')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover image ──────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: coverUrl != null
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Category + Status row ──────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _BrandGradient.c2.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category,
                        style: textTheme.labelSmall?.copyWith(
                          color: _BrandGradient.c2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Title ─────────────────────────────────────────────────
                Text(
                  property.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1530),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Price ─────────────────────────────────────────────────
                Text(
                  property.priceDisplay,
                  style: textTheme.titleSmall?.copyWith(
                    color: _BrandGradient.c2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Location ──────────────────────────────────────────────
                if (property.location.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: scheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          property.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),

                // ── Created date ──────────────────────────────────────────
                if (property.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: scheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(property.createdAt),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // ── Action buttons ────────────────────────────────────────
                Row(
                  children: [
                    _ActionButton(
                      label: 'View',
                      icon: Icons.open_in_new_rounded,
                      color: _BrandGradient.c2,
                      onTap: () {},
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      color: Colors.orange,
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFEEECF8),
      child: const Center(
        child: Icon(
          Icons.home_work_outlined,
          size: 48,
          color: Color(0xFFBBB6E0),
        ),
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final effectiveColor = disabled ? Colors.grey.shade400 : color;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: effectiveColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: effectiveColor.withOpacity(disabled ? 0.2 : 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
