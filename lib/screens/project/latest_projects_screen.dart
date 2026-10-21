// screens/project/latest_projects_screen.dart
//
// Public "browse all" projects list — the destination for the Home
// "Popular Categories" Premium Projects tile (`category_icon_grid.dart`),
// mirroring the portal's `LatestProjects.tsx`: `builder_projects` filtered
// to active/approved, a client-side title/location filter, and a card
// list — reusing [ProjectCardVertical] and [ProjectService.listLatestActive]
// exactly as the Home "Latest Projects" rail already does, just with a much
// higher limit and no horizontal-scroll cap.
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/project_model.dart';
import '../../services/project_service.dart';
import '../../widgets/project_card_vertical.dart';

class LatestProjectsScreen extends StatefulWidget {
  const LatestProjectsScreen({super.key, this.service});

  @visibleForTesting
  final ProjectService? service;

  @override
  State<LatestProjectsScreen> createState() => _LatestProjectsScreenState();
}

class _LatestProjectsScreenState extends State<LatestProjectsScreen> {
  final TextEditingController _search = TextEditingController();
  late Future<List<ProjectModel>> _future = _load();
  String _query = '';

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

  Future<List<ProjectModel>> _load() =>
      (widget.service ?? ProjectService()).listLatestActive(limit: 200);

  List<ProjectModel> _filtered(List<ProjectModel> all) {
    if (_query.isEmpty) return all;
    return all
        .where(
          (project) =>
              project.title.toLowerCase().contains(_query) ||
              project.location.toLowerCase().contains(_query),
        )
        .toList();
  }

  void _openProject(ProjectModel project) {
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': project.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.sizeOf(context).width - 32;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Premium Projects',
          style: AppTextStyles.heading2.copyWith(fontSize: 17),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by project name or location',
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
            child: FutureBuilder<List<ProjectModel>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return EmptyStateView(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load projects",
                    message: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: () => setState(() => _future = _load()),
                  );
                }

                final results = _filtered(snapshot.data ?? const []);
                if (results.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.apartment_rounded,
                    title: 'No matches',
                    message: _query.isEmpty
                        ? 'Premium projects will appear here once approved.'
                        : 'Try a different name or location.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: results.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ProjectCardVertical(
                      project: results[index],
                      width: cardWidth,
                      onTap: () => _openProject(results[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
