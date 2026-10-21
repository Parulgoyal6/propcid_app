import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/project_model.dart';
import '../services/project_likes_service.dart';
import '../services/project_service.dart';
import '../services/saved_projects_service.dart';

/// Like/save state for projects the viewer does not own — backs My
/// Activity's Projects filter. Unlike [PropertyProvider]/`ReelsProvider`,
/// there is no general "all projects" browse cache to filter locally (a
/// user's liked/saved projects may belong to any builder), so the liked/saved
/// rows themselves are fetched directly by id via [ProjectService.fetchByIds]
/// rather than filtered out of an already-loaded list.
class ProjectsProvider with ChangeNotifier {
  final ProjectService _projectService = ProjectService();
  final ProjectLikesService _projectLikesService = ProjectLikesService();
  final SavedProjectsService _savedProjectsService = SavedProjectsService();

  final Set<String> _likedProjectIds = {};
  final Set<String> _savedProjectIds = {};
  List<ProjectModel> _likedProjects = [];
  List<ProjectModel> _savedProjects = [];

  bool isLiked(String projectId) => _likedProjectIds.contains(projectId);
  bool isSaved(String projectId) => _savedProjectIds.contains(projectId);

  ProjectsProvider() {
    _loadLikedProjects();
    _loadSavedProjects();
  }

  Future<void> _loadLikedProjects() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final ids = await _projectLikesService.fetchLikedProjectIds(userId);
      _likedProjectIds
        ..clear()
        ..addAll(ids);
      _likedProjects = await _projectService.fetchByIds(ids.toList());
      notifyListeners();
    } catch (e) {
      debugPrint('[ProjectsProvider] _loadLikedProjects failed: $e');
    }
  }

  Future<void> _loadSavedProjects() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final ids = await _savedProjectsService.fetchSavedProjectIds(userId);
      _savedProjectIds
        ..clear()
        ..addAll(ids);
      _savedProjects = await _projectService.fetchByIds(ids.toList());
      notifyListeners();
    } catch (e) {
      debugPrint('[ProjectsProvider] _loadSavedProjects failed: $e');
    }
  }

  /// Optimistically toggles, then persists to `user_likes`; rolls back on
  /// failure — same pattern as `PropertyProvider.toggleLike`/
  /// `ReelsProvider.toggleLike`. [project] is the row the caller already has
  /// in hand (e.g. the open project detail screen) so a newly-liked project
  /// appears in [getLikedProjects] immediately, without a extra fetch.
  Future<void> toggleLike(String projectId, {ProjectModel? project}) async {
    final wasLiked = _likedProjectIds.contains(projectId);
    if (wasLiked) {
      _likedProjectIds.remove(projectId);
      _likedProjects.removeWhere((p) => p.id == projectId);
    } else {
      _likedProjectIds.add(projectId);
      if (project != null && !_likedProjects.any((p) => p.id == projectId)) {
        _likedProjects.add(project);
      }
    }
    notifyListeners();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (wasLiked) {
        await _projectLikesService.unlike(userId, projectId);
      } else {
        await _projectLikesService.like(userId, projectId);
      }
    } catch (e) {
      debugPrint('[ProjectsProvider] toggleLike persistence failed: $e');
      if (wasLiked) {
        _likedProjectIds.add(projectId);
        if (project != null && !_likedProjects.any((p) => p.id == projectId)) {
          _likedProjects.add(project);
        }
      } else {
        _likedProjectIds.remove(projectId);
        _likedProjects.removeWhere((p) => p.id == projectId);
      }
      notifyListeners();
    }
  }

  /// Same optimistic/rollback shape as [toggleLike], persisting to
  /// `saved_projects` instead.
  Future<void> toggleSave(String projectId, {ProjectModel? project}) async {
    final wasSaved = _savedProjectIds.contains(projectId);
    if (wasSaved) {
      _savedProjectIds.remove(projectId);
      _savedProjects.removeWhere((p) => p.id == projectId);
    } else {
      _savedProjectIds.add(projectId);
      if (project != null && !_savedProjects.any((p) => p.id == projectId)) {
        _savedProjects.add(project);
      }
    }
    notifyListeners();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (wasSaved) {
        await _savedProjectsService.unsave(userId, projectId);
      } else {
        await _savedProjectsService.save(userId, projectId);
      }
    } catch (e) {
      debugPrint('[ProjectsProvider] toggleSave persistence failed: $e');
      if (wasSaved) {
        _savedProjectIds.add(projectId);
        if (project != null && !_savedProjects.any((p) => p.id == projectId)) {
          _savedProjects.add(project);
        }
      } else {
        _savedProjectIds.remove(projectId);
        _savedProjects.removeWhere((p) => p.id == projectId);
      }
      notifyListeners();
    }
  }

  List<ProjectModel> getLikedProjects() => _likedProjects;
  List<ProjectModel> getSavedProjects() => _savedProjects;
}
