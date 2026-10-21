import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../screens/dashboard/widgets/builder_offer_editor_sheet.dart';
import '../../../screens/dashboard/widgets/builder_section_kit.dart';
import '../../../services/builder_sections_service.dart';
import '../../../services/project_service.dart';
import 'team_tab_states.dart';

/// The Team Workspace's Marketed Offers tab.
///
/// Deliberately NOT filtered by the membership's `project_ids`. The portal's
/// own `FilteredOffersList` — mounted here as `role="builder"`
/// (`TeamMemberDashboard.tsx:225`) — takes no project-scoping prop at all and
/// shows every one of the builder's active offers regardless of the viewer's
/// membership scope, even though `builder_project_offers` RLS itself IS
/// project-scoped (`has_team_permission(builder_id,'offers',project_id)`).
/// This tab reproduces the portal's actual (unscoped) behavior faithfully —
/// matching it, not "fixing" a gap this phase wasn't asked to close.
///
/// Edit and Delete reuse the exact same pieces the builder's own dashboard
/// does (`BuilderOffersSection`, left untouched) — `BuilderOfferEditorSheet`
/// for the form and `BuilderOfferService.update/delete` for the write.
/// Neither assumes the signed-in user is the offer's owner: the sheet never
/// reads `AuthProvider`, and both service calls are scoped by the ids passed
/// in, so authorization is left entirely to `builder_project_offers`'s own
/// RLS (`has_team_permission(builder_id,'offers',project_id)` for a team
/// member).
///
/// **Create is deliberately absent.** The portal's own `FilteredOffersList`
/// has no create button anywhere in it — the create flow
/// (`MarketToBrokersModal` in create mode) is only reachable from
/// `BuilderProjectsManager.tsx:835`, a builder-only screen that is not part
/// of `TeamMemberDashboard` at all. Adding a Create action here would be
/// inventing behavior the portal's Team Workspace does not have.
class TeamOffersTab extends StatefulWidget {
  const TeamOffersTab({super.key, required this.builderId});

  final String builderId;

  @override
  State<TeamOffersTab> createState() => _TeamOffersTabState();
}

class _TeamOffersTabState extends State<TeamOffersTab> {
  final BuilderOfferService _offers = BuilderOfferService();
  final ProjectService _projects = ProjectService();

  bool _loading = true;
  String? _error;
  List<BuilderOffer> _offerList = const [];
  List<ProjectModel> _projectList = const [];
  String? _busyOfferId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the builder's projects alongside their offers — needed only to
  /// seed `BuilderOfferEditorSheet`'s image picker on edit
  /// (`BuilderOffersSection._edit`'s exact reasoning: "Needs the offer's
  /// project for the image picker"). Never used to filter the offer list
  /// itself.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _offers.listMine(widget.builderId),
        _projects.listMine(widget.builderId),
      ]);
      if (!mounted) return;
      setState(() {
        _offerList = results[0] as List<BuilderOffer>;
        _projectList = results[1] as List<ProjectModel>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load offers. Please try again.';
        _loading = false;
      });
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openProject(BuilderOffer offer) {
    final projectId = offer.projectId;
    if (projectId == null) return;
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': projectId},
    );
  }

  Future<void> _edit(BuilderOffer offer) async {
    final matches = _projectList.where((p) => p.id == offer.projectId).toList();
    if (matches.isEmpty) {
      _toast("That offer's project is no longer available.", isError: true);
      return;
    }

    final draft = await showModalBottomSheet<BuilderOfferDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          BuilderOfferEditorSheet(project: matches.first, editing: offer),
    );
    if (draft == null || !mounted) return;

    setState(() => _busyOfferId = offer.id);
    try {
      await _offers.update(
        offerId: offer.id,
        payload: draft.toPayload(isCreate: false),
      );
      if (!mounted) return;
      _toast('Offer updated.');
      await _load();
    } catch (_) {
      _toast('Could not update that offer. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  Future<void> _delete(BuilderOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Offer'),
        content: Text(
          'Delete "${offer.title}"?\n\n'
          'Brokers this was marketed to will no longer see it. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyOfferId = offer.id);
    try {
      await _offers.delete(offer.id);
      if (!mounted) return;
      setState(() {
        _offerList = _offerList.where((o) => o.id != offer.id).toList();
        _busyOfferId = null;
      });
      _toast('Offer deleted.');
    } catch (_) {
      if (mounted) setState(() => _busyOfferId = null);
      _toast('Could not delete that offer. Please try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return TeamTabErrorState(message: _error!, onRetry: _load);
    }
    if (_offerList.isEmpty) {
      return const TeamTabEmptyState(message: 'No active offers right now.');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        itemCount: _offerList.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.spacingM),
        itemBuilder: (context, index) {
          final offer = _offerList[index];
          return _OfferCard(
            offer: offer,
            busy: _busyOfferId == offer.id,
            onTap: () => _openProject(offer),
            onEdit: () => _edit(offer),
            onDelete: () => _delete(offer),
          );
        },
      ),
    );
  }
}

/// Same layout as `BuilderOffersSection`'s own `_OfferCard` — View / Edit /
/// Delete over a cover, title, project line and description — reproduced
/// here rather than imported, since that one is private to its file.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.busy,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final BuilderOffer offer;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return BuilderSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (offer.projectTitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        offer.projectLocation == null
                            ? offer.projectTitle!
                            : '${offer.projectTitle} · ${offer.projectLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
              const BuilderPill(label: 'Active', tint: AppColors.success),
            ],
          ),
          if (offer.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              offer.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ],
          const SizedBox(height: AppConstants.spacingM),
          const Divider(height: 1, color: AppColors.hairline),
          const SizedBox(height: 6),
          if (busy)
            const BuilderActionBusyRow()
          else
            Row(
              children: [
                Expanded(
                  child: BuilderAction(
                    icon: Icons.open_in_new_rounded,
                    label: 'View',
                    onTap: offer.projectId == null ? null : onTap,
                  ),
                ),
                Expanded(
                  child: BuilderAction(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    onTap: onEdit,
                  ),
                ),
                Expanded(
                  child: BuilderAction(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    tint: AppColors.error,
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
