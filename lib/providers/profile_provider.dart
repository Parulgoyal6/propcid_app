import 'package:flutter/foundation.dart';

import '../models/article_summary.dart';
import '../models/influencer_video_model.dart';
import '../models/profile_stats.dart';
import '../models/property_model.dart';
import '../services/article_service.dart';
import '../services/influencer_video_service.dart';
import '../services/network_service.dart';
import '../services/profile_view_service.dart';
import '../services/property_service.dart';
import '../services/ratings_service.dart';

/// State for the Profile root screen: the three stat counts plus the user's
/// own content.
///
/// Follows the shape of `IndividualDashboardProvider` (blueprint §1.2.1) — a
/// plain ChangeNotifier over services, loaded from the view's post-frame
/// callback.
///
/// The stat tiles and the content lists load independently so one slow or
/// failing query never blanks the rest of the screen.
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    NetworkService? networkService,
    RatingsService? ratingsService,
    ProfileViewService? profileViewService,
    PropertyService? propertyService,
    ArticleService? articleService,
    InfluencerVideoService? influencerVideoService,
  }) : _networkService = networkService ?? NetworkService(),
       _ratingsService = ratingsService ?? RatingsService(),
       _profileViewService = profileViewService ?? ProfileViewService(),
       _propertyService = propertyService ?? PropertyService(),
       _articleService = articleService ?? ArticleService(),
       _influencerVideoService =
           influencerVideoService ?? InfluencerVideoService();

  final NetworkService _networkService;
  final RatingsService _ratingsService;
  final ProfileViewService _profileViewService;
  final PropertyService _propertyService;
  final ArticleService _articleService;
  final InfluencerVideoService _influencerVideoService;

  String? _lastUserId;

  ProfileStats _stats = ProfileStats.zero;
  bool _statsLoading = true;
  bool _statsFailed = false;

  List<PropertyModel> _properties = const [];
  List<ArticleSummary> _articles = const [];
  List<InfluencerVideoModel> _videos = const [];
  bool _contentLoading = true;
  bool _contentFailed = false;

  ProfileStats get stats => _stats;
  bool get statsLoading => _statsLoading;
  bool get statsFailed => _statsFailed;

  List<PropertyModel> get properties => List.unmodifiable(_properties);
  List<ArticleSummary> get articles => List.unmodifiable(_articles);
  List<InfluencerVideoModel> get videos => List.unmodifiable(_videos);
  bool get contentLoading => _contentLoading;
  bool get contentFailed => _contentFailed;

  bool get hasAnyContent =>
      _properties.isNotEmpty || _articles.isNotEmpty || _videos.isNotEmpty;

  Future<void> load(String userId) async {
    _lastUserId = userId;
    await Future.wait([_loadStats(userId), _loadContent(userId)]);
  }

  Future<void> refresh() async {
    final userId = _lastUserId;
    if (userId == null) return;
    await load(userId);
  }

  Future<void> _loadStats(String userId) async {
    _statsLoading = true;
    _statsFailed = false;
    notifyListeners();

    try {
      // Three independent tables — fetched concurrently rather than serially.
      final results = await Future.wait([
        _networkService.getAcceptedCount(userId),
        _ratingsService.getRatingSummary(userId),
        _profileViewService.getCount(userId),
      ]);

      final ratings = results[1] as ({int count, double average});
      _stats = ProfileStats(
        followers: results[0] as int,
        reviews: ratings.count,
        profileViews: results[2] as int,
        averageRating: ratings.average,
      );
    } catch (e) {
      debugPrint('ProfileProvider._loadStats failed: $e');
      _statsFailed = true;
      _stats = ProfileStats.zero;
    } finally {
      _statsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadContent(String userId) async {
    _contentLoading = true;
    _contentFailed = false;
    notifyListeners();

    try {
      // Fetched unconditionally, same as the portal's `fetchUserVideos` —
      // gating "Videos" to influencer accounts happens at the tab-visibility
      // layer (`MyContentSection.showVideosTab`), not here; a non-influencer
      // simply has no rows in `influencer_videos`.
      final results = await Future.wait([
        _propertyService.getPropertiesByUser(userId),
        _articleService.listOwn(userId),
        _influencerVideoService.listMine(userId),
      ]);

      _properties = results[0] as List<PropertyModel>;
      _articles = results[1] as List<ArticleSummary>;
      _videos = results[2] as List<InfluencerVideoModel>;
    } catch (e) {
      debugPrint('ProfileProvider._loadContent failed: $e');
      _contentFailed = true;
      _properties = const [];
      _articles = const [];
      _videos = const [];
    } finally {
      _contentLoading = false;
      notifyListeners();
    }
  }
}
