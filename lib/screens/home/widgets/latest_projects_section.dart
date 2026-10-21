// screens/home/widgets/latest_projects_section.dart
//
// Home's genuine "Latest Projects" rail — `builder_projects`, newest active
// + approved first. This is the *project* counterpart to the "New Listings"
// property rail in `home_screen.dart`; the two used to share one title
// ("Latest Projects") while both actually rendered `properties` rows, which
// is precisely the property/project conflation this rail exists to fix.
// Mirrors the portal's `LatestProjectsSection.tsx`.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW — same convention as every
// other admin/backend-driven Home rail.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../models/project_model.dart';
import '../../../services/project_service.dart';
import '../../../widgets/project_card_vertical.dart';
import '../../../widgets/section_header.dart';

class LatestProjectsSection extends StatefulWidget {
  const LatestProjectsSection({super.key, this.service});

  @visibleForTesting
  final ProjectService? service;

  @override
  State<LatestProjectsSection> createState() => _LatestProjectsSectionState();
}

class _LatestProjectsSectionState extends State<LatestProjectsSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying `builder_projects` every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<ProjectModel>> _future =
      (widget.service ?? ProjectService()).listLatestActive();

  void _openProject(BuildContext context, ProjectModel project) {
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': project.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (AppConstants.propertyCardWidth * dpr).round();
    final cacheHeight = (AppConstants.propertyCardImageHeight * dpr).round();
    return FutureBuilder<List<ProjectModel>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final projects = snapshot.data ?? const <ProjectModel>[];

        if (!loading && projects.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Latest Projects'),
              SizedBox(
                height: AppConstants.propertyCardHeight,
                child: loading
                    ? ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: 3,
                        itemBuilder: (context, index) =>
                            const PropertyCardShimmer(),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: projects.length,
                        itemBuilder: (context, index) => ProjectCardVertical(
                          project: projects[index],
                          imageCacheWidth: cacheWidth,
                          imageCacheHeight: cacheHeight,
                          onTap: () => _openProject(context, projects[index]),
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
