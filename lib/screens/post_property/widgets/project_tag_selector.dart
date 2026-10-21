import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../models/tagged_project.dart';
import '../../../providers/post_property_provider.dart';
import '../../../services/property_service.dart';

/// Optional builder-project tag — the Flutter counterpart of React's
/// `ProjectTagSelector` (features/property/ProjectTagSelector.tsx).
///
/// A broker listing a unit inside a developer's project links it here, so the
/// listing shows which project it belongs to and appears on that project's
/// page. Tag only: this cannot create or edit projects, and the inventory
/// subsystem is out of scope for this migration.
///
/// Flutter keeps its own widgets and styling; only the data contract — which
/// projects are offered, and what selecting one writes — matches React.
class ProjectTagSelector extends StatefulWidget {
  const ProjectTagSelector({super.key});

  @override
  State<ProjectTagSelector> createState() => _ProjectTagSelectorState();
}

class _ProjectTagSelectorState extends State<ProjectTagSelector> {
  final PropertyService _service = PropertyService();
  final TextEditingController _searchController = TextEditingController();
  late final TextEditingController _builderNameController;

  Timer? _debounce;
  List<TaggedProject> _results = const [];
  bool _loading = false;
  String? _error;

  /// The currently tagged project, loaded when editing a listing that already
  /// carries a tag so the chip can show its name rather than a bare id.
  TaggedProject? _tagged;

  @override
  void initState() {
    super.initState();
    final provider = context.read<PostPropertyProvider>();
    _builderNameController = TextEditingController(text: provider.builderName);
    if (provider.projectId.isNotEmpty) _loadTagged(provider.projectId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _builderNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTagged(String id) async {
    try {
      final project = await _service.fetchTaggedProject(id);
      if (mounted && project != null) setState(() => _tagged = project);
    } catch (_) {
      // A tag that cannot be resolved still shows via the stored project name;
      // failing to load it must not break the wizard.
    }
  }

  void _onSearchChanged(String term) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(term));
  }

  Future<void> _search(String term) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<PostPropertyProvider>();
      final results = await _service.searchBuilderProjects(
        term: term,
        city: provider.city,
      );
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load projects.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();

    return WizardCard(
      icon: Icons.apartment_outlined,
      title: 'Builder Project (Optional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'If this property is a unit inside a developer\'s project, tag it '
            'here — buyers will see the project it belongs to.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (provider.hasProjectTag)
            _TaggedChip(
              title: _tagged?.title.isNotEmpty == true
                  ? _tagged!.title
                  : (provider.projectName.isNotEmpty
                        ? provider.projectName
                        : 'Tagged project'),
              location: _tagged?.location ?? provider.projectLocation,
              onClear: () {
                setState(() => _tagged = null);
                context.read<PostPropertyProvider>().selectProject(null);
              },
            )
          else ...[
            WizardTextField(
              controller: _searchController,
              hint: 'Search projects by name or location',
              prefixIcon: Icons.search,
              onChanged: _onSearchChanged,
            ),
            if (_loading) ...[
              const SizedBox(height: 10),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._results.map(
                (p) => _ProjectRow(
                  project: p,
                  onTap: () {
                    setState(() {
                      _tagged = p;
                      _results = const [];
                      _searchController.clear();
                    });
                    final prov = context.read<PostPropertyProvider>();
                    prov.selectProject(p);
                    // selectProject may adopt the project's builder name;
                    // mirror it into the field the user can still edit.
                    _builderNameController.text = prov.builderName;
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          WizardField(
            label: 'Builder / Developer Name',
            child: WizardTextField(
              controller: _builderNameController,
              hint: 'e.g., Prestige Group',
              prefixIcon: Icons.business_outlined,
              onChanged: (v) =>
                  context.read<PostPropertyProvider>().setBuilderName(v),
            ),
          ),
          if (!provider.hasProjectTag)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No project in the list? Type the builder name here.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaggedChip extends StatelessWidget {
  const _TaggedChip({
    required this.title,
    required this.location,
    required this.onClear,
  });

  final String title;
  final String location;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (location.isNotEmpty)
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.textSecondary,
            onPressed: onClear,
            tooltip: 'Remove tag',
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.onTap});

  final TaggedProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: project.thumbnail != null
                    ? Image.network(
                        project.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.primaryLight,
                          child: const Icon(
                            Icons.apartment,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.primaryLight,
                        child: const Icon(
                          Icons.apartment,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      project.location,
                      if (project.builderName?.isNotEmpty ?? false)
                        project.builderName!,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
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
}
