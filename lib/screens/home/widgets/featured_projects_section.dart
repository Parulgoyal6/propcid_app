// screens/home/widgets/featured_projects_section.dart
//
// Home's "Featured Projects" rail — the *project* (`builder_projects`)
// counterpart to `FeaturedPropertiesSection`'s *property* (`properties`)
// rail. Mirrors the portal's "Featured Projects" swiper
// (`PublicHomePage.tsx` / `AuthenticatedHomePage.tsx`), sourced from the
// admin-curated `featured_projects` join table via
// [FeaturedProjectsService].
//
// No "See all" action: the portal's destination is a dedicated
// `/featured-projects` list page (`FeaturedProjects.tsx`) that this app has
// no equivalent screen for, and building one is outside the Homepage's
// scope. Same reasoning applies to `LatestProjectsSection`.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW — same convention as every
// other admin-curated Home rail (NewsSection, TrendingCitiesSection, ...).
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../models/project_model.dart';
import '../../../services/featured_projects_service.dart';
import '../../../widgets/project_card_vertical.dart';
import '../../../widgets/section_header.dart';

class FeaturedProjectsSection extends StatefulWidget {
  const FeaturedProjectsSection({super.key, this.service});

  @visibleForTesting
  final FeaturedProjectsService? service;

  @override
  State<FeaturedProjectsSection> createState() =>
      _FeaturedProjectsSectionState();
}

class _FeaturedProjectsSectionState extends State<FeaturedProjectsSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying `featured_projects` every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<ProjectModel>> _future =
      (widget.service ?? FeaturedProjectsService()).listActive();

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
              const SectionHeader(title: 'Featured Projects'),
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
