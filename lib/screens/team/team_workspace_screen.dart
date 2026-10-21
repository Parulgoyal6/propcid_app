import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/builder_section_options.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/builder_section_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import 'widgets/team_inventory_tab.dart';
import 'widgets/team_leads_tab.dart';
import 'widgets/team_offers_tab.dart';
import 'widgets/team_site_visits_tab.dart';
import 'widgets/team_tab_states.dart';

/// Mobile mirror of the portal's `/team-workspace` (`TeamMemberDashboard.tsx`).
///
/// Loads nothing of its own beyond one refresh call:
/// [AuthProvider.activeTeamMemberships] is already the same read
/// `AuthProvider._checkTeamStatus`/`refreshTeamStatus` populate, so the list
/// itself is never re-queried here — only [AuthProvider.refreshTeamStatus] is
/// called once on mount, which re-runs that same existing read so a
/// membership revoked since the app last checked no longer appears, without
/// adding a poll or a duplicate query.
class TeamWorkspaceScreen extends StatefulWidget {
  const TeamWorkspaceScreen({
    super.key,
    this.initialBuilderId,
    this.initialModule,
  });

  /// Pre-selects this builder's membership instead of the first one in the
  /// list — e.g. a tapped project-visit notification knows which builder's
  /// workspace the project belongs to. Falls back to the first membership,
  /// same as today, when null or no longer active.
  final String? initialBuilderId;

  /// One of `['inventory','offers','leads','site_visits']` to open on
  /// instead of whichever tab is first for the selected membership. Ignored
  /// if that membership doesn't grant the module (the tab wouldn't exist).
  final String? initialModule;

  @override
  State<TeamWorkspaceScreen> createState() => _TeamWorkspaceScreenState();
}

class _TeamWorkspaceScreenState extends State<TeamWorkspaceScreen> {
  String? _selectedBuilderId;
  bool _refreshing = true;

  @override
  void initState() {
    super.initState();
    _selectedBuilderId = widget.initialBuilderId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    await context.read<AuthProvider>().refreshTeamStatus();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final memberships = context.watch<AuthProvider>().activeTeamMemberships;

    Widget body;
    if (_refreshing) {
      body = const Center(child: CircularProgressIndicator());
    } else if (memberships.isEmpty) {
      // Covers both "never had access" and point 13's "the membership I was
      // last looking at was revoked" — either way, an empty active list is
      // the same state to show.
      body = const TeamTabEmptyState(
        message: 'You do not have team access to any builder right now.',
      );
    } else {
      // The previously selected builder may no longer be in the list (its
      // membership just got revoked) — fall back to the first remaining one
      // rather than rendering a stale selection.
      final selected = memberships.firstWhere(
        (m) => m.builderId == _selectedBuilderId,
        orElse: () => memberships.first,
      );
      _selectedBuilderId = selected.builderId;

      body = _WorkspaceBody(
        key: ValueKey(selected.builderId),
        memberships: memberships,
        selected: selected,
        initialModule: widget.initialModule,
        onBuilderChanged: (builderId) =>
            setState(() => _selectedBuilderId = builderId),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Team Workspace', style: AppTextStyles.heading3),
      ),
      body: body,
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    super.key,
    required this.memberships,
    required this.selected,
    required this.onBuilderChanged,
    this.initialModule,
  });

  final List<BuilderTeamMember> memberships;
  final BuilderTeamMember selected;
  final ValueChanged<String?> onBuilderChanged;
  final String? initialModule;

  @override
  Widget build(BuildContext context) {
    final builderId = selected.builderId ?? '';
    // Null ⇒ every one of the builder's projects (`BuilderTeamMember.hasAllProjects`).
    final allowedProjectIds = selected.projectIds;

    final tabs = <_ModuleTab>[
      // Only modules this membership actually grants get a tab — never every
      // module unconditionally.
      if (selected.modules.contains('inventory'))
        _ModuleTab(
          module: 'inventory',
          label: builderTeamModuleLabel('inventory'),
          icon: Icons.apartment_outlined,
          child: TeamInventoryTab(
            builderId: builderId,
            allowedProjectIds: allowedProjectIds,
          ),
        ),
      if (selected.modules.contains('offers'))
        _ModuleTab(
          module: 'offers',
          label: builderTeamModuleLabel('offers'),
          icon: Icons.local_offer_outlined,
          child: TeamOffersTab(builderId: builderId),
        ),
      if (selected.modules.contains('leads'))
        _ModuleTab(
          module: 'leads',
          label: builderTeamModuleLabel('leads'),
          icon: Icons.contact_mail_outlined,
          child: TeamLeadsTab(builderId: builderId),
        ),
      if (selected.modules.contains('site_visits'))
        _ModuleTab(
          module: 'site_visits',
          label: builderTeamModuleLabel('site_visits'),
          icon: Icons.event_available_outlined,
          child: TeamSiteVisitsTab(
            builderId: builderId,
            allowedProjectIds: allowedProjectIds,
          ),
        ),
    ];

    if (tabs.isEmpty) {
      return const TeamTabEmptyState(
        message: 'This membership has no modules granted yet.',
      );
    }

    final initialIndex = initialModule == null
        ? 0
        : tabs.indexWhere((tab) => tab.module == initialModule).clamp(
            0,
            tabs.length - 1,
          );

    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Column(
        children: [
          if (memberships.length > 1)
            _BuilderSelector(
              memberships: memberships,
              selectedBuilderId: selected.builderId,
              onChanged: onBuilderChanged,
            ),
          Container(
            color: AppColors.cardBackground,
            child: TabBar(
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [
                for (final tab in tabs)
                  Tab(text: tab.label, icon: Icon(tab.icon)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [for (final tab in tabs) tab.child]),
          ),
        ],
      ),
    );
  }
}

class _ModuleTab {
  const _ModuleTab({
    required this.module,
    required this.label,
    required this.icon,
    required this.child,
  });

  final String module;
  final String label;
  final IconData icon;
  final Widget child;
}

/// "Managing for: [ ABC Builders ▼ ]" — shown only when this person has more
/// than one active membership. Switching changes which builder's modules and
/// project scope the tabs below read.
class _BuilderSelector extends StatefulWidget {
  const _BuilderSelector({
    required this.memberships,
    required this.selectedBuilderId,
    required this.onChanged,
  });

  final List<BuilderTeamMember> memberships;
  final String? selectedBuilderId;
  final ValueChanged<String?> onChanged;

  @override
  State<_BuilderSelector> createState() => _BuilderSelectorState();
}

class _BuilderSelectorState extends State<_BuilderSelector> {
  final AuthService _authService = AuthService();
  final Map<String, String> _names = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  /// `builder_team_members` carries no display name — same reason the
  /// pending-invitation screen resolves it separately: only
  /// `accept-team-invite`'s success response includes one, and only for the
  /// invitation just accepted, not for every membership. Resolves every
  /// builder in [BuilderSelector.memberships] once, in parallel, rather than
  /// one query per dropdown item.
  Future<void> _loadNames() async {
    final ids = widget.memberships
        .map((m) => m.builderId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final results = await Future.wait(
      ids.map((id) async {
        try {
          final profile = await _authService.getUserProfile(id);
          final company = profile?['company_name']?.toString();
          final name = profile?['display_name']?.toString();
          final label = (company != null && company.isNotEmpty)
              ? company
              : (name != null && name.isNotEmpty ? name : 'A builder');
          return MapEntry(id, label);
        } catch (_) {
          return MapEntry(id, 'A builder');
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      _names.addEntries(results);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.cardBackground,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: AppConstants.spacingM,
      ),
      child: Row(
        children: [
          Text(
            'Managing for',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          Expanded(
            child: _loading
                ? Text('Loading…', style: AppTextStyles.body)
                : DropdownButton<String>(
                    isExpanded: true,
                    value: widget.selectedBuilderId,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final m in widget.memberships)
                        DropdownMenuItem(
                          value: m.builderId,
                          child: Text(
                            _names[m.builderId] ?? 'A builder',
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                    onChanged: widget.onChanged,
                  ),
          ),
        ],
      ),
    );
  }
}
