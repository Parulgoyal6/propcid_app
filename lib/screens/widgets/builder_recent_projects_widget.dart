import 'package:flutter/material.dart';

import '../../models/builder_project_model.dart';
import '../../services/builder_project_service.dart';

class BuilderRecentProjectsWidget extends StatelessWidget {
  final String builderId;

  const BuilderRecentProjectsWidget({super.key, required this.builderId});

  Widget _shimmerLoading(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 220,
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return Colors.green;
      case 'active':
      case 'ongoing':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<List<BuilderProjectModel>>(
      future: BuilderProjectService().getProjects(builderId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "My Projects",
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 15),
              _shimmerLoading(context),
            ],
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: scheme.error),
                const SizedBox(width: 10),
                Text(
                  "Error loading projects",
                  style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ],
            ),
          );
        }

        final projects = snapshot.data ?? [];

        if (projects.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.apartment_rounded,
                  size: 40,
                  color: scheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  "No projects found",
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "My Projects",
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 15),
            ...projects.map((project) {
              final statusColor = _statusColor(project.status, scheme);

              return TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 10),
                    child: child,
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withOpacity(0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (project.image.isNotEmpty)
                        Stack(
                          children: [
                            Image.network(
                              project.image,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  height: 180,
                                  color: scheme.surfaceContainerHighest
                                      .withOpacity(0.4),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.35),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  project.status,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              project.title,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 16,
                                  color: scheme.onSurface.withOpacity(0.5),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    project.location,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(
                                  Icons.visibility_rounded,
                                  size: 18,
                                  color: scheme.onSurface.withOpacity(0.45),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  project.views.toString(),
                                  style: textTheme.bodySmall,
                                ),
                                const SizedBox(width: 18),
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  project.likes.toString(),
                                  style: textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Divider(color: scheme.outline.withOpacity(0.12)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Available: ${project.availableUnits}",
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                Text(
                                  "₹${project.minPrice.toInt()} - ₹${project.maxPrice.toInt()}",
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
