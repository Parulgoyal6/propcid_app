import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/scale_tap.dart';
import '../../models/network_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_section_provider.dart';
import '../../widgets/shared/stat_kpi_card.dart';
import '../shared/section_loader.dart';
import 'widgets/network_screen_shell.dart';

/// Network ▸ My Leads — the design's `isMyLeads` screen.
///
/// Four status counts over the lead list, from `network_leads`.
///
/// Read-only: assigning a lead, changing its status and editing the assignment
/// rules are all writes (React drives them through `lead_assignment_rules` and
/// the `assign-lead-automatically` function), so the "Settings" control opens
/// the shared placeholder rather than a form that cannot save.
class MyLeadsScreen extends StatelessWidget {
  const MyLeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkLeadsSection(),
      child: const _MyLeadsView(),
    );
  }
}

class _MyLeadsView extends StatefulWidget {
  const _MyLeadsView();

  @override
  State<_MyLeadsView> createState() => _MyLeadsViewState();
}

class _MyLeadsViewState extends State<_MyLeadsView>
    with DeferredSectionLoader<_MyLeadsView> {
  // This screen branches on `AuthProvider.userType` (builder vs. member reads
  // different `network_leads` columns) — see `loadSection` below. Without
  // this, a builder whose first load races ahead of role resolution would be
  // permanently cached as a member. See the field's own doc.
  @override
  bool get reloadOnRoleChange => true;

  @override
  void loadSection(String userId) {
    final isBuilder =
        context.read<AuthProvider>().userType?.toLowerCase() == 'builder';
    context.read<NetworkLeadsSection>().loadFor(userId, isBuilder: isBuilder);
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<NetworkLeadsSection>();

    return MyLeadsBody(
      leads: section.value,
      loading: section.loading,
      failed: section.failed,
      onSettings: () => openSectionPlaceholder(context, 'Lead Settings'),
    );
  }
}

class MyLeadsBody extends StatelessWidget {
  final List<NetworkLead> leads;
  final bool loading;
  final bool failed;
  final VoidCallback onSettings;

  const MyLeadsBody({
    super.key,
    required this.leads,
    required this.loading,
    required this.failed,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final counts = LeadStatusCounts.fromLeads(leads);
    // An em dash rather than a zero when the query failed, so "no data" is
    // never mistaken for "you have no leads".
    String count(int value) => failed ? '—' : '$value';

    return NetworkScreenShell(
      title: 'My Leads',
      subtitle: 'Distribute and track network leads',
      children: [
        const SizedBox(height: 18),
        NetworkIntroBanner(
          title: 'Lead Distribution System',
          description:
              'Manage and distribute leads to your network members efficiently',
          trailing: _SettingsPill(onTap: onSettings),
        ),
        const SizedBox(height: 14),
        if (loading)
          const MetricCardGridShimmer(count: 4)
        else
          MetricCardGrid(
            cards: [
              MetricCard(
                icon: Icons.schedule,
                value: count(counts.pending),
                label: 'Pending',
                accent: AppColors.warning,
              ),
              MetricCard(
                icon: Icons.arrow_forward_rounded,
                value: count(counts.assigned),
                label: 'Assigned',
              ),
              MetricCard(
                icon: Icons.chat_bubble_outline,
                value: count(counts.contacted),
                label: 'Contacted',
                accent: AppColors.amenityBlue,
              ),
              MetricCard(
                icon: Icons.check_circle_outline,
                value: count(counts.converted),
                label: 'Converted',
                accent: AppColors.success,
              ),
            ],
          ),
        const SizedBox(height: 18),
        NetworkTitledCard(
          icon: Icons.track_changes,
          title: 'Network Leads',
          child: _buildList(),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (failed) {
      return const Padding(
        padding: EdgeInsets.only(top: AppConstants.spacingXXL),
        child: EmptyStateView(
          icon: Icons.error_outline,
          title: "Couldn't load your leads",
          message: 'Try again in a moment.',
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      );
    }

    if (leads.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: AppConstants.spacingXXL),
        child: EmptyStateView(
          icon: Icons.track_changes,
          title: 'No Leads Available',
          message:
              'Leads will appear here when customers submit inquiries '
              'through your properties or projects.',
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < leads.length; i++) ...[
          SizedBox(height: i == 0 ? AppConstants.spacingL : 10),
          _LeadRow(lead: leads[i]),
        ],
      ],
    );
  }
}

class _SettingsPill extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lead settings',
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.settings_outlined,
                size: 15,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                'Settings',
                style: AppTextStyles.body.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  final NetworkLead lead;

  const _LeadRow({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lead.leadType.isEmpty ? 'Lead' : lead.leadType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              NetworkStatusPill(
                lead.status,
                positive: lead.status == 'converted',
              ),
            ],
          ),
          const SizedBox(height: 8),
          NetworkDetailRow(label: 'Priority', value: lead.priority),
          NetworkDetailRow(
            label: 'Assignment',
            value: lead.autoAssigned ? 'Automatic' : lead.assignmentMethod,
          ),
        ],
      ),
    );
  }
}
