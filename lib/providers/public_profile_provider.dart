// providers/public_profile_provider.dart
//
// State for the Public Profile screen.
//
// SCREEN-SCOPED, NOT GLOBAL
// -------------------------
// Created inside `PublicProfileScreen` via `ChangeNotifierProvider`, the same way
// `ProfileScreen` creates `ProfileProvider`. Two reasons, beyond following the
// established pattern: a global instance would keep one user's profile in memory
// after navigating to another, and registering it globally would mean editing
// `main.dart` and `test/widget_test.dart`, which the approved scope excludes.
//
// FOUR INDEPENDENT SECTIONS
// -------------------------
// Identity, connection, content and ratings each carry their own loading and
// failure flags — the shape `ProfileProvider` established. A slow reviews query
// must not blank the header, and a failed one must not lose the listings. The
// screen renders each section against its own flag.
//
// Identity resolves first because the rest depends on it: `user_type` decides
// whether to fetch properties or builder projects, and whether the rating shown
// is the customer average or the total.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/builder_project_model.dart';
import '../models/profile_review.dart';
import '../models/property_model.dart';
import '../models/user_profile.dart';
import '../services/network_service.dart';
import '../services/profile_connection_service.dart';
import '../services/profile_content_service.dart';
import '../services/profile_rating_service.dart';
import '../services/profile_view_service.dart';
import '../services/user_profile_service.dart';

class PublicProfileProvider extends ChangeNotifier {
  PublicProfileProvider({
    UserProfileService? profileService,
    ProfileContentService? contentService,
    ProfileConnectionService? connectionService,
    NetworkService? networkService,
    ProfileViewService? profileViewService,
    ProfileRatingService? ratingService,
  }) : _ratingService = ratingService ?? ProfileRatingService(),
       _profileService = profileService ?? UserProfileService(),
       _contentService = contentService ?? ProfileContentService(),
       _connectionService = connectionService ?? ProfileConnectionService(),
       // The existing NetworkService is REUSED by calling its unchanged
       // `getAcceptedCount()`. Nothing in that file is modified.
       _networkService = networkService ?? NetworkService(),
       // Same for ProfileViewService: Phase 2 appended `recordView()` beside the
       // untouched `getCount()`.
       _profileViewService = profileViewService ?? ProfileViewService();

  final UserProfileService _profileService;
  final ProfileContentService _contentService;
  final ProfileConnectionService _connectionService;
  final NetworkService _networkService;
  final ProfileViewService _profileViewService;

  /// Companion write path. `RatingsService` stays read-only and untouched.
  final ProfileRatingService _ratingService;

  String? _userId;
  String? _viewerId;
  bool _disposed = false;

  // ── Identity ──────────────────────────────────────────────────────────────
  UserProfile? _profile;
  bool _profileLoading = true;
  bool _profileFailed = false;
  bool _profileNotFound = false;

  UserProfile? get profile => _profile;
  bool get profileLoading => _profileLoading;
  bool get profileFailed => _profileFailed;

  /// The query succeeded but matched no row — a removed or bad id. Distinct from
  /// [profileFailed], and it gets its own copy on screen.
  bool get profileNotFound => _profileNotFound;

  /// True while nothing but a skeleton can be drawn.
  bool get isInitialLoad => _profileLoading && _profile == null;

  /// The viewer is looking at their own profile.
  bool get isSelf =>
      _viewerId != null && _userId != null && _viewerId == _userId;

  bool get viewerSignedIn => _viewerId != null && _viewerId!.isNotEmpty;

  // ── Connection ────────────────────────────────────────────────────────────
  ProfileConnectionStatus _connectionStatus = ProfileConnectionStatus.none;
  int _connectionsCount = 0;
  bool _connectionLoading = true;
  bool _connectionFailed = false;

  ProfileConnectionStatus get connectionStatus => _connectionStatus;
  int get connectionsCount => _connectionsCount;
  bool get connectionLoading => _connectionLoading;
  bool get connectionFailed => _connectionFailed;

  /// Contact details are visible to a connected viewer and to the owner.
  ///
  /// The portal's rule verbatim (UserProfile.tsx:1520) — and the columns are only
  /// present in the row when the viewer is signed in anyway, so this gate and the
  /// column gate agree.
  bool get canSeeContactDetails => _connectionStatus.isConnected || isSelf;

  // ── Content ───────────────────────────────────────────────────────────────
  List<PropertyModel> _properties = const [];
  List<BuilderProjectModel> _projects = const [];
  bool _contentLoading = true;
  bool _contentFailed = false;

  List<PropertyModel> get properties => List.unmodifiable(_properties);
  List<BuilderProjectModel> get projects => List.unmodifiable(_projects);
  bool get contentLoading => _contentLoading;
  bool get contentFailed => _contentFailed;

  /// Builders publish projects; everyone else publishes listings.
  bool get showsProjects => _profile?.isBuilder ?? false;

  /// The count behind the first stat tile.
  int get contentCount => showsProjects ? _projects.length : _properties.length;

  bool get hasContent => contentCount > 0;

  // ── Ratings ───────────────────────────────────────────────────────────────
  RatingBreakdown _ratings = RatingBreakdown.zero;
  bool _ratingsLoading = true;
  bool _ratingsFailed = false;

  RatingBreakdown get ratings => _ratings;
  bool get ratingsLoading => _ratingsLoading;
  bool get ratingsFailed => _ratingsFailed;

  /// The headline rating: customers only for a builder, everyone otherwise.
  RatingSummary get displayRating =>
      _ratings.displayFor(isBuilder: _profile?.isBuilder ?? false);

  // ── The viewer's own rating (Phase 5) ─────────────────────────────────────
  MyRating? _myRating;
  bool _submittingRating = false;

  MyRating? get myRating => _myRating;
  bool get submittingRating => _submittingRating;

  /// Whether to offer the rating sheet at all.
  ///
  /// Signed in, not looking at themselves. The RLS insert check enforces both
  /// (`auth.uid() = rater_id AND auth.uid() <> rated_user_id`); this keeps the
  /// button from appearing where it could only fail.
  bool get canRate => viewerSignedIn && !isSelf && _profile != null;

  /// Submits or updates, then reloads the aggregates so the summary, the
  /// distribution and the review list all reflect the change.
  ///
  /// Returns null on success, or a user-facing message.
  Future<String?> submitRating({required int rating, String? review}) async {
    final userId = _userId;
    if (userId == null || !canRate) return 'You cannot rate this profile.';
    if (_submittingRating) return null;

    _submittingRating = true;
    _safeNotify();

    try {
      final existing = _myRating;
      final error = existing == null
          ? await _ratingService.submitRating(
              viewerId: _viewerId,
              ratedUserId: userId,
              rating: rating,
              review: review,
            )
          : await _ratingService.updateRating(
              viewerId: _viewerId,
              ratedUserId: userId,
              ratingId: existing.id,
              rating: rating,
              review: review,
            );

      if (error != null) return _messageFor(error);

      // Re-read both: the aggregates for the section, and `myRating` so the
      // button flips to "Update your review" and a second submit updates rather
      // than colliding with the unique index.
      await Future.wait([_loadRatings(), _loadMyRating()]);
      return null;
    } finally {
      _submittingRating = false;
      _safeNotify();
    }
  }

  static String _messageFor(RatingWriteError error) {
    switch (error) {
      case RatingWriteError.alreadyRated:
        return 'You have already rated this user.';
      case RatingWriteError.notAllowed:
        return 'You cannot rate this profile.';
      case RatingWriteError.failed:
        return 'Could not save your rating. Please try again.';
    }
  }

  // ── Connection actions (Phase 6) ──────────────────────────────────────────
  bool _connectionBusy = false;
  bool get connectionBusy => _connectionBusy;

  /// Whether the connect control should accept a tap.
  ///
  /// `connected` is terminal — the portal renders it as an inert badge, and there
  /// is no "disconnect" flow on either platform.
  bool get canActOnConnection =>
      viewerSignedIn &&
      !isSelf &&
      _profile != null &&
      _connectionStatus != ProfileConnectionStatus.connected;

  /// One handler for all three transitions, mirroring the portal's single
  /// `handleNetworkAction` rather than three separate buttons.
  ///
  /// Returns null on success, or a user-facing message. On success the connection
  /// state is re-read from the database rather than assumed, so a concurrent
  /// change by the other party cannot leave the button lying.
  Future<String?> actOnConnection() async {
    final userId = _userId;
    if (userId == null || !canActOnConnection) {
      return 'You cannot connect with this profile.';
    }
    if (_connectionBusy) return null;

    _connectionBusy = true;
    _safeNotify();

    try {
      final ConnectionWriteError? error;
      switch (_connectionStatus) {
        case ProfileConnectionStatus.none:
          error = await _connectionService.sendRequest(
            viewerId: _viewerId,
            profileUserId: userId,
          );
        case ProfileConnectionStatus.pendingSent:
          error = await _connectionService.cancelRequest(
            viewerId: _viewerId,
            profileUserId: userId,
          );
        case ProfileConnectionStatus.pendingReceived:
          error = await _connectionService.acceptRequest(
            viewerId: _viewerId,
            profileUserId: userId,
          );
        case ProfileConnectionStatus.connected:
          return null;
      }

      // Re-read either way. After a failure the local status may already be
      // wrong — a `nothingToAccept` means the request was withdrawn — so
      // refreshing is what stops the button showing a stale state.
      await _loadConnection();

      return error == null ? null : _connectionMessageFor(error);
    } finally {
      _connectionBusy = false;
      _safeNotify();
    }
  }

  static String _connectionMessageFor(ConnectionWriteError error) {
    switch (error) {
      case ConnectionWriteError.notAllowed:
        return 'You cannot connect with this profile.';
      case ConnectionWriteError.nothingToAccept:
        return 'That request is no longer available.';
      case ConnectionWriteError.failed:
        return 'Could not update the connection. Please try again.';
    }
  }

  Future<void> _loadMyRating() async {
    final userId = _userId;
    if (userId == null) return;
    _myRating = await _ratingService.fetchMyRating(
      viewerId: _viewerId,
      ratedUserId: userId,
    );
    _safeNotify();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Loads everything for [userId], as seen by [viewerId] (null when signed out).
  ///
  /// Safe to call again for the same pair — it simply reloads.
  Future<void> load({required String userId, required String? viewerId}) async {
    _userId = userId;
    _viewerId = viewerId;

    await _loadProfile();

    // Nothing else is meaningful without the profile: `user_type` chooses the
    // content query, and a missing row means there is nothing to load.
    if (_profile == null) {
      _contentLoading = false;
      _ratingsLoading = false;
      _connectionLoading = false;
      _safeNotify();
      return;
    }

    // Phase 2: log the visit for the owner's "Profile Views" list.
    //
    // Deliberately NOT awaited and NOT inside the Future.wait below. It is
    // fire-and-forget: the RPC never fails the screen, and putting it on the
    // critical path would delay the sections the user is waiting for. Fired only
    // after the profile resolved, so a 404 or an error never records a view.
    unawaited(
      _profileViewService.recordView(
        viewerId: _viewerId,
        profileUserId: userId,
      ),
    );

    await Future.wait([
      _loadConnection(),
      _loadContent(),
      _loadRatings(),
      _loadMyRating(),
    ]);
  }

  /// Re-runs every query. Backs pull-to-refresh.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    await load(userId: userId, viewerId: _viewerId);
  }

  /// Retries only the section that failed, so a retry tap does not re-fetch three
  /// healthy sections.
  Future<void> retryContent() => _loadContent();
  Future<void> retryRatings() => _loadRatings();

  Future<void> _loadProfile() async {
    _profileLoading = true;
    _profileFailed = false;
    _profileNotFound = false;
    _safeNotify();

    try {
      final userId = _userId!;
      // Own profile goes through the AuthService path the app already uses;
      // anyone else's goes through the column-gated public read.
      final profile = isSelf
          ? await _profileService.fetchOwn(userId)
          : await _profileService.fetchPublic(
              userId,
              viewerSignedIn: viewerSignedIn,
            );

      _profile = profile;
      _profileNotFound = profile == null;
    } catch (e) {
      debugPrint('PublicProfileProvider._loadProfile failed: $e');
      _profileFailed = true;
      _profile = null;
    } finally {
      _profileLoading = false;
      _safeNotify();
    }
  }

  Future<void> _loadConnection() async {
    _connectionLoading = true;
    _connectionFailed = false;
    _safeNotify();

    try {
      final userId = _userId!;
      final results = await Future.wait([
        _connectionService.getStatus(
          viewerId: _viewerId,
          profileUserId: userId,
        ),
        _networkService.getAcceptedCount(userId),
      ]);

      _connectionStatus = results[0] as ProfileConnectionStatus;
      _connectionsCount = results[1] as int;
    } catch (e) {
      debugPrint('PublicProfileProvider._loadConnection failed: $e');
      _connectionFailed = true;
      // Fails closed: an unknown connection state keeps contact details hidden.
      _connectionStatus = ProfileConnectionStatus.none;
      _connectionsCount = 0;
    } finally {
      _connectionLoading = false;
      _safeNotify();
    }
  }

  Future<void> _loadContent() async {
    _contentLoading = true;
    _contentFailed = false;
    _safeNotify();

    try {
      final userId = _userId!;
      if (showsProjects) {
        _projects = await _contentService.fetchBuilderProjects(
          userId,
          viewerIsOwner: isSelf,
        );
        _properties = const [];
      } else {
        _properties = await _contentService.fetchProperties(userId);
        _projects = const [];
      }
    } catch (e) {
      debugPrint('PublicProfileProvider._loadContent failed: $e');
      _contentFailed = true;
      _properties = const [];
      _projects = const [];
    } finally {
      _contentLoading = false;
      _safeNotify();
    }
  }

  Future<void> _loadRatings() async {
    _ratingsLoading = true;
    _ratingsFailed = false;
    _safeNotify();

    try {
      _ratings = await _contentService.fetchRatings(_userId!);
    } catch (e) {
      debugPrint('PublicProfileProvider._loadRatings failed: $e');
      _ratingsFailed = true;
      _ratings = RatingBreakdown.zero;
    } finally {
      _ratingsLoading = false;
      _safeNotify();
    }
  }

  /// Every load path can complete after the screen has been popped — the four
  /// sections finish independently and none is cancellable. Notifying a disposed
  /// ChangeNotifier throws, so the flag is checked first. `SocialSection` in the
  /// Social module guards the same way.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
