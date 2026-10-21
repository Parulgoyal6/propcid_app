// screens/property_detail/property_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/overlay_toast.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/compare_toggle_handler.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/property_area_formatter.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../providers/chat_thread_provider.dart';
import '../../providers/compare_provider.dart';
import '../../providers/property_provider.dart';
import '../../models/feed_item.dart';
import '../../services/feed_service.dart';
import '../feed/feed_screen.dart' show FeedItemCard;
import '../../models/reel_comment.dart';
import '../../services/comment_service.dart';
import '../../services/messaging_service.dart';
import '../messaging/chat_thread_screen.dart';
import 'widgets/share_property_sheet.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/amenity_icon_tile.dart';
import '../../widgets/nearby_place_row.dart';
import '../../widgets/property_map_widget.dart';
import '../../widgets/property_card_horizontal.dart';
import '../../widgets/emi_calculator_widget.dart';
import 'property_media_viewer_screen.dart';
import '../../services/nearby_places_service.dart';
import '../../services/property_inquiry_service.dart';
import '../../services/property_service.dart';
import '../../services/session_service.dart';
import '../../services/visit_booking_service.dart';
import '../../providers/auth_provider.dart';
import 'booking_enquiry_validation.dart';
import '../../models/nearby_place.dart';
import '../../models/property_model.dart';
import '../../models/property_detail_bundle.dart';
import '../post_property/listing_constants.dart'
    show
        ListingOption,
        kAreaUnitLabels,
        kPgRoomAmenities,
        kPgSafetyAndSecurity,
        kResidentialTenantPreferences,
        kPgTenantRules,
        kHouseSubtypes;

// =============================================================================
// PropertyDetailScreen
// Displays full details of a single property: hero image carousel, highlights,
// property information grid, expandable description, amenities, location
// map, nearby places, related properties, an inline EMI calculator (for
// sell-type properties), and action buttons for scheduling visits/enquiries.
//
// Fetches its property via a dedicated PropertyService.getPropertyDetail
// call (the website's exact 3-query shape) rather than an in-memory lookup,
// so deep-linked or paginated-away properties still resolve correctly. Also
// tracks a view (track_property_view RPC) after a 3s watch-time, matching
// the website's own view-tracking behavior.
// =============================================================================
class PropertyDetailScreen extends StatefulWidget {
  final String propertyId;

  /// Injectable for tests — default to real, Supabase-backed services when
  /// null.
  final VisitBookingService? visitBookingService;
  final PropertyInquiryService? inquiryService;

  const PropertyDetailScreen({
    super.key,
    required this.propertyId,
    this.visitBookingService,
    this.inquiryService,
  });

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _isDescriptionExpanded = false;
  bool _showAllAmenities = false;
  bool _showAllNearby = false;

  /// Collapsed "Additional Details" group titles — purely local presentation
  /// state (which groups are currently visible), same pattern the Compare
  /// Properties screen's section headers already use. Never affects what
  /// data is fetched or shown once expanded.
  final Set<String> _collapsedDetailGroups = {};

  void _toggleDetailGroup(String title) {
    setState(() {
      if (_collapsedDetailGroups.contains(title)) {
        _collapsedDetailGroups.remove(title);
      } else {
        _collapsedDetailGroups.add(title);
      }
    });
  }

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // Drives the hero image carousel and its counter chip.
  late final PageController _imagePageController;
  int _currentImageIndex = 0;

  // Live "Nearby Places" state, fetched from Places API (New) via
  // NearbyPlacesService — unrelated to Supabase, left exactly as-is.
  final NearbyPlacesService _nearbyPlacesService = NearbyPlacesService();
  List<NearbyPlace> _nearbyPlaces = <NearbyPlace>[];
  bool _isLoadingNearbyPlaces = true;

  // Dedicated single-property fetch (properties/profiles/subtype tables),
  // matching PropertyDetails.tsx's exact 3-query shape.
  final PropertyService _propertyService = PropertyService();
  PropertyModel? _property;
  PropertyOwnerProfile? _ownerProfile;
  String? _contactEmail;
  String? _contactPhone;
  bool _isLoadingProperty = true;
  String? _loadError;
  bool _isLoadingOwnershipDocs = false;

  late final VisitBookingService _visitBookingService =
      widget.visitBookingService ?? VisitBookingService();

  List<PropertyModel> _relatedProperties = <PropertyModel>[];
  bool _isLoadingRelated = true;

  /// The same related properties as Feed-shaped items, so they render with the
  /// Feed's own card. Empty if that lookup fails - the section then falls back
  /// to the original horizontal cards.
  List<FeedItem> _relatedFeedItems = <FeedItem>[];

  Timer? _viewTrackingTimer;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();

    // Subtle one-shot entrance animation for the content card beneath the
    // hero image. Kept intentionally light per the "no heavy animations" rule.
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    _entranceController.forward();

    _loadProperty();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _imagePageController.dispose();
    _viewTrackingTimer?.cancel();
    super.dispose();
  }

  /// Instant-paints from whatever's already loaded in memory (if anything),
  /// then always resolves the authoritative dedicated fetch in the
  /// background and swaps it in — this is what lets a deep-linked or
  /// paginated-away property still load correctly, unlike the old pure
  /// in-memory `getPropertyById` lookup.
  Future<void> _loadProperty() async {
    final PropertyProvider propertyProvider = Provider.of<PropertyProvider>(
      context,
      listen: false,
    );
    final cached = propertyProvider.findCached(widget.propertyId);
    if (cached != null && mounted) {
      setState(() => _property = cached);
    }

    try {
      final PropertyDetailBundle bundle = await _propertyService
          .getPropertyDetail(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _property = bundle.property;
        _ownerProfile = bundle.ownerProfile;
        _contactEmail = bundle.contactEmail;
        _contactPhone = bundle.contactPhone;
        _isLoadingProperty = false;
      });
      _loadNearbyPlaces();
      _loadRelatedProperties();
      _startViewTracking();
    } catch (e) {
      debugPrint('[PropertyDetail] getPropertyDetail failed: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingProperty = false;
        if (_property == null) {
          _loadError = 'Property not found';
        }
      });
    }
  }

  /// Loads real nearby places for this property's coordinates. Never throws
  /// into the widget tree — any failure just leaves the list empty so the
  /// UI shows the "No nearby places found" state instead of crashing.
  Future<void> _loadNearbyPlaces() async {
    final property = _property;
    if (property == null) {
      if (mounted) setState(() => _isLoadingNearbyPlaces = false);
      return;
    }

    try {
      final List<NearbyPlace> results = await _nearbyPlacesService
          .fetchNearbyPlaces(
            latitude: property.latitude,
            longitude: property.longitude,
          );
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = results;
        _isLoadingNearbyPlaces = false;
      });
    } on NearbyPlacesException catch (e) {
      debugPrint('[PropertyDetail] Nearby places unavailable: $e');
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = <NearbyPlace>[];
        _isLoadingNearbyPlaces = false;
      });
    } catch (e) {
      debugPrint('[PropertyDetail] Nearby places fetch failed: $e');
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = <NearbyPlace>[];
        _isLoadingNearbyPlaces = false;
      });
    }
  }

  /// Ports RelatedPropertyCards.tsx: same property_type + category, similar
  /// city, approved, excluding self.
  Future<void> _loadRelatedProperties() async {
    final property = _property;
    if (property == null ||
        property.propertyType == null ||
        property.category == null) {
      if (mounted) setState(() => _isLoadingRelated = false);
      return;
    }

    try {
      final related = await _propertyService.getRelatedProperties(
        propertyId: property.id,
        propertyType: property.propertyType!,
        category: property.category!,
        location: property.location,
      );
      var feedItems = <FeedItem>[];
      try {
        feedItems = await FeedService().fetchPropertyItems([
          for (final p in related) p.id,
        ]);
      } catch (e) {
        debugPrint('[PropertyDetail] Related feed items failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _relatedProperties = related;
        _relatedFeedItems = feedItems;
        _isLoadingRelated = false;
      });
    } catch (e) {
      debugPrint('[PropertyDetail] Related properties fetch failed: $e');
      if (!mounted) return;
      setState(() {
        _relatedProperties = <PropertyModel>[];
        _isLoadingRelated = false;
      });
    }
  }

  /// Tracks a view via the track_property_view RPC after a 3s watch-time —
  /// matches the website's useViewTracking hook exactly (a quick bounce
  /// before the timer fires doesn't count; the RPC itself enforces a
  /// 30-minute per-user/session dedupe window server-side).
  void _startViewTracking() {
    final property = _property;
    if (property == null) return;

    _viewTrackingTimer?.cancel();
    _viewTrackingTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final sessionId = await SessionService.getSessionId();
        if (!mounted) return;
        await _propertyService.trackPropertyView(
          propertyId: property.id,
          viewerUserId: Supabase.instance.client.auth.currentUser?.id,
          viewerSessionId: sessionId,
          viewDurationSeconds: 3,
          viewPercentage: 100,
        );
      } catch (e) {
        debugPrint('[PropertyDetail] View tracking failed: $e');
      }
    });
  }

  /// Resolves the full gallery for a property, always falling back
  /// to the single legacy `imageUrl` when `imageUrls` is empty, so older
  /// cached/mocked PropertyModel instances keep working unchanged.
  /// Whether a `media_urls` entry is a video. Same extension test the portal
  /// uses when assembling media_urls (PropertyWizard.tsx `isVideoUrl`), plus
  /// the common phone formats; the query string is ignored.
  static final RegExp _videoExtension = RegExp(
    r'\.(mp4|webm|ogg|mov|avi|m4v|mkv|3gp)$',
    caseSensitive: false,
  );
  static bool _isVideoUrl(String url) =>
      _videoExtension.hasMatch(url.split('?').first);

  List<String> _resolveImages(dynamic property) {
    final List<String> urls =
        (property.resolvedImageUrls as List<String>?) ?? const [];
    if (urls.isNotEmpty) return urls;
    final String single = property.imageUrl as String? ?? '';
    return single.isNotEmpty ? [single] : const [];
  }

  @override
  Widget build(BuildContext context) {
    if (_property == null) {
      if (_isLoadingProperty) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      }
      return Scaffold(
        body: Center(child: Text(_loadError ?? 'Property not found')),
      );
    }

    final property = _property!;
    final PropertyProvider propertyProvider = Provider.of<PropertyProvider>(
      context,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // -----------------------------------------------------------------
          // Hero SliverAppBar with image carousel, back button, actions, chips
          // -----------------------------------------------------------------
          SliverAppBar(
            expandedHeight: AppConstants.propertyDetailHeroHeight,
            pinned: true,
            // Disable Flutter's automatic back button to avoid double arrows
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildHeroImageCarousel(context, property),
                  _buildGradientOverlay(),
                  _buildTopActions(context, property, propertyProvider),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: _buildPhotoCountChip(property),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: _buildVirtualTourChip(context, property),
                  ),
                ],
              ),
            ),
          ),

          // -----------------------------------------------------------------
          // Scrollable content card beneath the hero image
          // -----------------------------------------------------------------
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.surface,
                        Color.alphaBlend(
                          AppColors.primary.withValues(alpha: 0.04),
                          AppColors.surface,
                        ),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            gradient: AppColors.ctaGradient,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (property.isVerified)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: VerifiedBadge(),
                              ),

                            // Title
                            Text(
                              property.title,
                              style: AppTextStyles.heading2.copyWith(
                                fontSize: 21,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Price on a gradient pill, rate beside it
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.ctaGradient,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    property.priceDisplay,
                                    style: AppTextStyles.price.copyWith(
                                      color: Colors.white,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                if (property.pricePerSqft.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      property.pricePerSqft,
                                      style: AppTextStyles.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Location, in a soft tinted box
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      size: 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        _fullAddress(property),
                                        style: AppTextStyles.caption.copyWith(
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Property Highlights
                            _buildHighlightsRow(property),

                            const SizedBox(height: 20),

                            // Expandable description — moved above the
                            // Property Information grid on explicit request
                            // (the portal itself renders description AFTER
                            // its overview grid, so this is a deliberate
                            // Flutter-only presentation choice, not a
                            // parity fix).
                            _buildExpandableDescription(property),

                            const SizedBox(height: 20),

                            // Property Information grid
                            _buildPropertyInformationGrid(context, property),

                            const SizedBox(height: 20),

                            // Additional details — the long-tail wizard
                            // fields (RERA, facing, legal approvals,
                            // utilities, pricing overflow, contact prefs)
                            // stored in `properties.metadata`. Mirrors the
                            // portal's renderAdditionalDetails/
                            // renderExtendedDetails grouping.
                            // (Now rendered together with the Property Information
                            // tiles above, grouped by listing-form step.)

                            // Ownership Documents (Land only) — owner-only,
                            // same visibility rule the portal's
                            // `handleViewOwnershipDocuments` relies on.
                            _buildOwnershipDocumentsSection(property),

                            // Tags — mirrors the portal's "Tags" card
                            // (PropertyDetails.tsx:2719-2732), right after
                            // Extended/Additional Details and before the map.
                            _buildHashtagsSection(property),

                            // Posted by (owner/broker) — mirrors the
                            // portal's "Contact Seller" block. Hidden
                            // entirely when no owner profile resolved.
                            if (_ownerProfile != null) ...[
                              _buildOwnerSection(context),
                              const SizedBox(height: 20),
                            ],

                            // Property Location map card
                            _buildLocationSection(context, property),

                            const SizedBox(height: 20),

                            // Amenities — mirrors the portal's own guard
                            // (PropertyDetails.tsx:2968, `property.amenities
                            // && property.amenities.length > 0`), which
                            // skips the whole card, heading included, when
                            // empty. A Land listing's wizard never collects
                            // generic amenities at all (same on both
                            // platforms — the Amenities step doesn't exist
                            // for Land), so without this guard every Land
                            // listing showed an "Amenities" heading over a
                            // blank 128px gap.
                            if ((property.amenities as List).isNotEmpty) ...[
                              _buildAmenitiesSection(property),
                              const SizedBox(height: 20),
                            ],

                            // Nearby places
                            _buildNearbyPlacesSection(property),

                            // EMI calculator — embedded inline for sell-type
                            // properties only, self-contained/no pre-filled
                            // amount, matching the website exactly.
                            if (property.propertyType == 'sell') ...[
                              const SizedBox(height: 20),
                              Text(
                                'EMI Calculator',
                                style: AppTextStyles.heading3,
                              ),
                              const SizedBox(height: 12),
                              const EmiCalculatorWidget(),
                            ],

                            const SizedBox(height: 20),

                            // Related properties
                            _buildRelatedPropertiesSection(context),

                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: _buildBottomBar(context, property, propertyProvider),
    );
  }

  // ===========================================================================
  // HERO IMAGE CAROUSEL
  // Swipeable PageView over resolvedImageUrls. Each page carries its own
  // Hero tag ('property_hero_<id>_<index>') so tapping a page flies it into
  // the matching page of GalleryViewerScreen.
  // ===========================================================================

  Widget _buildHeroImageCarousel(BuildContext context, dynamic property) {
    final images = _resolveImages(property);

    if (images.isEmpty) {
      return Container(
        color: AppColors.textHint.withOpacity(0.1),
        child: const Center(
          child: Icon(
            Icons.broken_image,
            color: AppColors.textSecondary,
            size: 48,
          ),
        ),
      );
    }

    return PageView.builder(
      controller: _imagePageController,
      itemCount: images.length,
      onPageChanged: (index) {
        setState(() => _currentImageIndex = index);
      },
      itemBuilder: (context, index) {
        // `media_urls` holds photos AND videos (the portal's wizard files a
        // "Property Video" into the same array) — a video URL handed to
        // CachedNetworkImage only ever rendered the broken-image icon.
        if (_isVideoUrl(images[index])) {
          return _PropertyVideoSlide(
            url: images[index],
            onTap: () => _openGallery(context, property, index),
          );
        }
        return GestureDetector(
          onTap: () => _openGallery(context, property, index),
          child: Hero(
            tag: 'property_hero_${property.id}_$index',
            // Subtle parallax: the photo drifts against the swipe, driven
            // directly by the PageController (same technique as the Home
            // hero banner) — no extra controller, nothing runs when idle.
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _imagePageController,
                builder: (context, child) {
                  double page = index.toDouble();
                  if (_imagePageController.hasClients &&
                      _imagePageController.position.haveDimensions) {
                    page = _imagePageController.page ?? page;
                  }
                  final delta = (page - index).clamp(-1.0, 1.0);
                  return OverflowBox(
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(-delta * 40, 0),
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width + 80,
                        child: child,
                      ),
                    ),
                  );
                },
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  fit: BoxFit.cover,
                  placeholder: (BuildContext ctx, String url) =>
                      const ShimmerBox(),
                  errorWidget: (BuildContext ctx, String url, Object error) {
                    debugPrint(
                      '[PropertyDetail] Image load error for ${property.id} '
                      '(index $index): $error',
                    );
                    return Container(
                      color: AppColors.textHint.withOpacity(0.1),
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: AppColors.textSecondary,
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradientOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TOP ACTIONS (back · share · favourite)
  // Favourite icon is keyed off PropertyProvider.isShortlisted (id-based,
  // backed by the persisted `saved_properties` table) rather than requiring
  // the property to already be in one of PropertyProvider's cached lists —
  // so a deep-linked property still shows/toggles the correct saved state.
  // ===========================================================================

  Widget _buildTopActions(
    BuildContext context,
    dynamic property,
    PropertyProvider propertyProvider,
  ) {
    final String propertyId = property.id as String;
    final bool isShortlisted = propertyProvider.isShortlisted(propertyId);
    final bool isLiked = propertyProvider.isLiked(propertyId);
    final bool isInCompare = context.watch<CompareProvider>().isSelected(
      propertyId,
    );

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleButton(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () {
                try {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                } catch (e) {
                  debugPrint('[PropertyDetail] Back navigation error: $e');
                }
              },
              padding: EdgeInsets.zero,
            ),
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(8),
          ),
          Row(
            children: [
              // Like — a real, separate action from Save/Shortlist below;
              // the reference backs it with `user_likes`, not
              // `saved_properties`. Heart icon, matching the reference's own
              // Like icon exactly (PropertyDetails.tsx / CombinedFeed.tsx use
              // `Heart` for Like and `Bookmark` for Save — never two hearts).
              GestureDetector(
                onTap: () => propertyProvider.toggleLike(propertyId),
                child: _buildCircleButton(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showPropertyComments(property),
                child: _buildCircleButton(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  child: const Icon(
                    Icons.mode_comment_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _shareProperty(property),
                child: _buildCircleButton(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  child: const Icon(Icons.share, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              // Save/Shortlist — switched from a second heart to a bookmark
              // icon. Direct consequence of the Like fix above: the
              // reference never shows two heart icons side by side — Like is
              // Heart, Save is Bookmark (PropertyDetails.tsx/CombinedFeed.tsx).
              // Behavior/state/persistence here are unchanged.
              GestureDetector(
                onTap: () => propertyProvider.toggleShortlist(propertyId),
                child: _buildCircleButton(
                  backgroundColor: Colors.white,
                  child: Icon(
                    isShortlisted ? Icons.bookmark : Icons.bookmark_border,
                    color: isShortlisted
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => handleCompareToggle(context, property),
                child: _buildCircleButton(
                  backgroundColor: Colors.white,
                  child: Icon(
                    isInCompare
                        ? Icons.check_circle
                        : Icons.compare_arrows_rounded,
                    color: isInCompare
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the same visible-link / Copy Link / Share pattern already used
  /// for profile sharing, mirroring the portal's PropertyShareModal (a
  /// readable, copyable link plus the system share sheet).
  void _shareProperty(dynamic property) {
    showSharePropertySheet(
      context,
      propertyId: property.id as String,
      title: (property.title as String?) ?? '',
      location: property.location as String?,
      priceDisplay: property.priceDisplay as String?,
      currentUserId: Provider.of<AuthProvider>(context, listen: false).userId,
    );
  }

  /// Reuses the same `post_comments` infrastructure already built for reels
  /// (`CommentService`/`ReelComment` — generic despite the name, keyed by
  /// postId+postType, not reel-specific), just with `post_type: 'property'`
  /// instead of `'video'`. No new comment system, no schema change.
  void _showPropertyComments(dynamic property) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PropertyCommentsSheet(
        propertyId: property.id as String,
        commentsEnabled: _ownerProfile?.commentsEnabled ?? true,
      ),
    );
  }

  Widget _buildCircleButton({
    required Color backgroundColor,
    required Widget child,
    BoxShape shape = BoxShape.circle,
    BorderRadius? borderRadius,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
      ),
      child: child,
    );
  }

  // ===========================================================================
  // BOTTOM CHIPS (photo counter · virtual tour)
  // ===========================================================================

  /// Shows the live "current/total" position in the carousel, doubling as
  /// the image counter.
  Widget _buildPhotoCountChip(dynamic property) {
    final images = _resolveImages(property);
    final total = images.length;
    if (total == 0) return const SizedBox.shrink();

    final current = (_currentImageIndex + 1).clamp(1, total);

    return _buildOverlayChip(
      children: [
        const Icon(Icons.camera_alt, color: Colors.white, size: 14),
        const SizedBox(width: 6),
        Text(
          '$current/$total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildVirtualTourChip(BuildContext context, dynamic property) {
    return GestureDetector(
      onTap: () => _handleVirtualTour(context, property),
      child: _buildOverlayChip(
        children: const [
          Icon(Icons.play_circle_outline, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            'Virtual Tour',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayChip({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: children),
    );
  }

  // ===========================================================================
  // NAVIGATION HELPERS
  // ===========================================================================

  /// Opens the media viewer on the tapped item. The viewer gets the WHOLE
  /// `media_urls` list - photos and videos together, in order - so the user
  /// can swipe on to the next item whatever it is (previously photos opened a
  /// photo-only viewer with the videos removed, and a video opened a separate
  /// single-video player, so neither could swipe to the other).
  void _openGallery(BuildContext context, dynamic property, int initialIndex) {
    final media = _resolveImages(property);
    if (media.isEmpty) return;

    debugPrint(
      '[PropertyDetail] Opening media viewer for property '
      '${property.id} at index $initialIndex of ${media.length}',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyMediaViewerScreen(
          media: media,
          initialIndex: initialIndex,
          // Same tag scheme as the carousel (indices now match, since the
          // viewer shows the full list), so a photo still flies into place.
          heroTagPrefix: 'property_hero_${property.id}',
        ),
      ),
    );
  }

  void _handleVirtualTour(BuildContext context, dynamic property) {
    debugPrint(
      '[PropertyDetail] Virtual Tour tapped for property: '
      '${property.id}',
    );

    final String? tourUrl = property.videoUrl;
    if (tourUrl != null && tourUrl.isNotEmpty) {
      try {
        Navigator.pushNamed(
          context,
          '/virtual-tour',
          arguments: {'url': tourUrl, 'title': property.title},
        );
      } catch (e) {
        debugPrint('[PropertyDetail] Virtual Tour navigation error: $e');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Virtual Tour Coming Soon'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ===========================================================================
  // PROPERTY HIGHLIGHTS
  // ===========================================================================

  Widget _buildHighlightsRow(dynamic property) {
    final List<_Highlight> highlights = [];

    if (property.isVerified == true) {
      highlights.add(
        _Highlight('Verified', Icons.verified, AppColors.verifiedBadge),
      );
    }
    if (property.isTrending == true) {
      highlights.add(
        _Highlight('Trending', Icons.trending_up, AppColors.warning),
      );
    }
    final String? possession = property.possessionStatus as String?;
    if (possession != null && possession.toLowerCase().contains('ready')) {
      highlights.add(
        _Highlight('Ready To Move', Icons.home_work, AppColors.success),
      );
    }
    // No "Featured" highlight: `isFeatured` is only a views >= 1 proxy (there is
    // no real featured flag on a listing), so it marked nearly every property.

    if (highlights.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: highlights
            .map(
              (h) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: h.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: h.color.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(h.icon, size: 14, color: h.color),
                    const SizedBox(width: 6),
                    Text(
                      h.label,
                      style: AppTextStyles.chip.copyWith(
                        color: h.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ===========================================================================
  // PROPERTY INFORMATION GRID
  // ===========================================================================

  Widget _buildPropertyInformationGrid(BuildContext context, dynamic property) {
    final double width = MediaQuery.of(context).size.width;
    final int crossAxisCount = width >= 900
        ? 4
        : width >= 600
        ? 3
        : 2;

    // Mirrors the portal's overviewItems builder (PropertyDetails.tsx),
    // which only ever pushes Bed/Bath items inside the
    // `property.category === "residential"` branch — land, commercial,
    // PG/co-living (category `pg_coliving`) and Other never get them there.
    // This used to check only `land`/`pg_coliving`, leaving commercial
    // shown — and for commercial, PropertyModel.beds/baths are repurposed to
    // carry the washrooms count (see property_model.dart's `fromSupabase`
    // commercial branch), so an Office listing with 2 washrooms and no
    // Bedrooms field anywhere in its wizard rendered "2 Bedrooms" here.
    final bool hidesBedsBaths = property.category != 'residential';

    // Each tile goes under the listing-form step that collects it, so the
    // page reads in the same order the seller filled the form in.
    final Map<String, List<_InfoItem>> tiles = {
      for (final step in _kListingStepTitles) step: <_InfoItem>[],
    };
    if (!hidesBedsBaths) {
      tiles[_kStepDimensions]!.add(
        _InfoItem(Icons.bed, 'Bedrooms', '${property.beds}'),
      );
      tiles[_kStepDimensions]!.add(
        _InfoItem(Icons.bathtub, 'Bathrooms', '${property.baths}'),
      );
      // `balconies` is a typed `properties_residential` column (saved
      // correctly) with no read site anywhere on this page until now.
      final int? balconies = property.balconies as int?;
      if (balconies != null) {
        tiles[_kStepDimensions]!.add(
          _InfoItem(Icons.balcony, 'Balconies', '$balconies'),
        );
      }
    } else if (property.category == 'commercial') {
      // `property.baths` holds the washrooms count for commercial
      // (PropertyModel.fromSupabase's commercial branch repurposes it) —
      // the bare number saves fine, it just had no "Washrooms"-labelled
      // tile of its own on this page.
      tiles[_kStepDimensions]!.add(
        _InfoItem(Icons.bathtub_outlined, 'Washrooms', '${property.baths}'),
      );
    }
    final int parkingSpaces = property.parking as int;
    if (parkingSpaces > 0) {
      tiles[_kStepDimensions]!.add(
        _InfoItem(Icons.local_parking, 'Parking', '$parkingSpaces'),
      );
    }
    // Land's value already reads e.g. "2500 Acres" — the unit word makes a
    // generic "Area" caption redundant underneath it (unlike other
    // categories, where the value is a bare number and the caption is the
    // only thing saying what it is), so it's dropped for Land specifically,
    // on request.
    tiles[_kStepDimensions]!.add(
      _InfoItem(
        Icons.square_foot,
        property.category == 'land' ? '' : 'Area',
        formatPropertyArea(property),
      ),
    );

    // `property.propertyType` is the listing intent (sell/rent/lease — see
    // `_insertProperty`'s `provider.listingIntent!.name`), not the property
    // type the wizard's Step 2 "Property Type" dropdown actually collects
    // (Apartment/Villa/... — `residential_subtype`). This tile is labelled
    // "Property Type" to match that step, so it has to read the matching
    // field.
    final String? residentialSubtype = property.residentialSubtype as String?;
    if (residentialSubtype != null && residentialSubtype.isNotEmpty) {
      tiles[_kStepBasic]!.add(
        _InfoItem(Icons.apartment, 'Property Type', residentialSubtype),
      );
    }
    // `bhkType` (metadata-only, residential) saved correctly but had no read
    // site on either this app's or the portal's own detail page — added
    // here since it's still collected and meaningful to a viewer.
    final Map<String, dynamic> metaForTiles =
        (property.metadata as Map<String, dynamic>?) ?? const {};
    if (property.category == 'residential') {
      final bhkType = metaForTiles['bhkType']?.toString();
      if (bhkType != null && bhkType.isNotEmpty) {
        tiles[_kStepBasic]!.add(
          _InfoItem(Icons.home_work_outlined, 'BHK Type', bhkType),
        );
      }
    }
    // `commercialType` — same "collected, saved, never shown" gap as
    // bhkType above, portal's own commercial overview-grid tile
    // (PropertyDetails.tsx, label "Commercial Type").
    if (property.category == 'commercial') {
      final commercialType = metaForTiles['commercialType']?.toString();
      if (commercialType != null && commercialType.isNotEmpty) {
        tiles[_kStepBasic]!.add(
          _InfoItem(Icons.business_outlined, 'Commercial Type', commercialType),
        );
      }
    }
    // `furnishedType` — portal shows this once, in the overview grid
    // (PropertyDetails.tsx, label "Furnishing"), for residential and
    // commercial alike. Collected by Flutter's Basic Info step for both,
    // never shown on this page before.
    if (property.category == 'residential' ||
        property.category == 'commercial') {
      final furnishedType = metaForTiles['furnishedType']?.toString();
      if (furnishedType != null && furnishedType.isNotEmpty) {
        tiles[_kStepBasic]!.add(
          _InfoItem(Icons.chair_outlined, 'Furnishing', furnishedType),
        );
      }
    }
    final double? carpetAreaSqft = property.carpetAreaSqft as double?;
    if (carpetAreaSqft != null && carpetAreaSqft > 0) {
      tiles[_kStepDimensions]!.add(
        _InfoItem(
          Icons.crop_square,
          'Carpet Area',
          '${_formatSqft(carpetAreaSqft)} sqft',
        ),
      );
    } else if (property.category == 'others') {
      // Others has no `properties_other*` sub-table at all (see
      // PropertyService._insertCategorySpecific's switch), so carpetAreaSqft
      // is always null for this category — its Carpet Area only ever lands
      // in metadata. Saved correctly, just never read back until now.
      final metaForCarpet =
          (property.metadata as Map<String, dynamic>?) ?? const {};
      final carpetArea = metaForCarpet['carpetArea']?.toString();
      if (carpetArea != null && carpetArea.isNotEmpty) {
        // Was missing a unit entirely (unlike every other category's
        // Carpet Area tile above, which at least hardcodes "sqft") —
        // Others' Carpet Area field shares the same unit control as its
        // Total Area field (property_dimensions_step.dart's `_areaBlock`,
        // "used for PG and Others"), so it's paired with `property.areaUnit`
        // the same way Commercial's Super Built-up Area is.
        final String carpetUnitLabel = property.areaUnit == null
            ? ''
            : (kAreaUnitLabels[property.areaUnit] ?? property.areaUnit);
        tiles[_kStepDimensions]!.add(
          _InfoItem(
            Icons.crop_square,
            'Carpet Area',
            '$carpetArea $carpetUnitLabel'.trim(),
          ),
        );
      }
    }
    // This column is NOT null/absent for every other category/subtype the
    // way the comment this replaced assumed — property_service.dart writes
    // `built_up_area_sqft: provider.area` unconditionally for Commercial
    // (`_insertCommercial`/`_upsertCommercial`, no distinct input exists)
    // and the same fallback applies to PG and Residential's Apartment
    // subtype (neither has a dedicated Build Up Area field either, so
    // `builtUpArea` text is always empty and `_insertResidential` falls
    // back to `provider.area` too). Only Residential's House subtypes
    // (Villa, Duplex, ...) have a genuinely distinct Build Up Area input —
    // everywhere else this tile was just the Area tile's own number
    // shown a second time under a different name.
    final double? builtUpAreaSqft = property.builtUpAreaSqft as double?;
    final bool builtUpAreaIsDistinct =
        property.category == 'residential' &&
        kHouseSubtypes.contains(residentialSubtype ?? '');
    if (builtUpAreaSqft != null &&
        builtUpAreaSqft > 0 &&
        builtUpAreaIsDistinct) {
      tiles[_kStepDimensions]!.add(
        _InfoItem(
          Icons.aspect_ratio,
          'Built-up Area',
          '${_formatSqft(builtUpAreaSqft)} sqft',
        ),
      );
    }
    // House subtypes (Villa, Duplex, ...) have no Floor No field anywhere in
    // the wizard — property_dimensions_step.dart's `_houseDimensions` has no
    // input for it at all (its own doc comment: "there is no Floor No").
    // But `floor_number` is written unconditionally on every residential
    // save (property_service.dart), so switching an existing apartment
    // listing's subtype to a house one (which doesn't clear the field)
    // left the old apartment's floor number stranded in the column and
    // this tile had no subtype check to hide it with.
    final bool isHouseSubtype =
        property.category == 'residential' &&
        kHouseSubtypes.contains(residentialSubtype ?? '');
    final int? floorNumber = property.floorNumber as int?;
    if (floorNumber != null && !isHouseSubtype) {
      tiles[_kStepDimensions]!.add(
        _InfoItem(Icons.stairs, 'Floor Number', '$floorNumber'),
      );
    }
    final int? totalFloors = property.totalFloors as int?;
    if (totalFloors != null && totalFloors > 0) {
      tiles[_kStepDimensions]!.add(
        _InfoItem(Icons.layers, 'Total Floors', '$totalFloors'),
      );
    }
    final String? possession = property.possessionStatus as String?;
    if (possession != null && possession.isNotEmpty) {
      // Same underlying value as the "Property Condition" row just above
      // (both read `metadata.propertyCondition`) — this tile is the one
      // that's actually prominent in the Property Information grid, so
      // moving only the row and not this tile left "Condition & Furnishing"
      // visibly populated for residential even after that move. No
      // "Possession" caption, on request — every other tile in this grid
      // keeps its caption; this is the one deliberate exception.
      final String possessionStep = property.category == 'residential'
          ? _kStepDimensions
          : _kStepCondition;
      tiles[possessionStep]!.add(
        _InfoItem(Icons.event_available, '', possession),
      );
    }
    final String pricePerSqft = property.pricePerSqft as String;
    if (pricePerSqft.isNotEmpty) {
      // The seller picks the rate unit separately in the Pricing step
      // (metadata.ratePerAreaUnit) — label with it, so a rate entered per
      // Square Yard isn't shown as "Price/SqFt". Rows without it keep SqFt.
      final Map meta = (property.metadata as Map?) ?? const {};
      final String rateUnit = meta['ratePerAreaUnit']?.toString() ?? '';
      final String rateLabel = rateUnit.isEmpty || rateUnit == 'sq_ft'
          ? 'Price/SqFt'
          : 'Price/${kAreaUnitLabels[rateUnit] ?? rateUnit}';
      tiles[_kStepPricing]!.add(
        _InfoItem(Icons.currency_rupee, rateLabel, pricePerSqft),
      );
    }
    // Mirrors the portal's overview grid, which only pushes this item when
    // `property.available_from` is set (PropertyDetails.tsx renderPropertyOverview).
    // `available_from` can hold the literal word "Immediately" (the
    // Dimensions step's "Immediately" checkbox — see PostPropertyProvider's
    // `availableImmediately` flag), which `DateTime.tryParse` can't
    // represent, so [PropertyModel.availableFrom] alone is always null for
    // such a listing. [availableFromRaw] preserves the original string so
    // that case still shows, instead of the whole tile silently vanishing.
    final DateTime? availableFrom = property.availableFrom as DateTime?;
    final String? availableFromRaw = property.availableFromRaw as String?;
    // Land has no Condition step at all — its own wizard collects
    // Available From on Dimensions instead (property_dimensions_step.dart's
    // `_availableFrom` helper, inside `_landDimensions`). Residential
    // collects it on Condition the same as commercial/PG, but groups it
    // under Dimensions & Layout here on request — a presentation choice for
    // residential specifically, not a parity correction; commercial/PG are
    // untouched.
    final String availableFromStep =
        (property.category == 'land' || property.category == 'residential')
        ? _kStepDimensions
        : _kStepCondition;
    if (availableFrom != null) {
      tiles[availableFromStep]!.add(
        _InfoItem(
          Icons.event,
          'Available From',
          _formatShortDate(availableFrom),
        ),
      );
    } else if (availableFromRaw != null &&
        availableFromRaw.trim().toLowerCase() == 'immediately') {
      tiles[availableFromStep]!.add(
        const _InfoItem(Icons.event, 'Available From', 'Immediately'),
      );
    }
    // Mirrors the portal's "Price Negotiable" chip (renderExtendedDetails'
    // Financial & Pricing group), which only appears when the flag is true.
    if (property.isNegotiable == true) {
      tiles[_kStepPricing]!.add(
        _InfoItem(Icons.handshake_outlined, 'Price', 'Negotiable'),
      );
    }

    return _buildAdditionalDetailsSection(
      property,
      tiles: tiles,
      tileColumns: crossAxisCount,
    );
  }

  static const List<String> _monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatShortDate(DateTime date) =>
      '${date.day} ${_monthAbbreviations[date.month - 1]} ${date.year}';

  /// Drops a trailing ".0" for a whole-number area (e.g. `950` not `950.0`),
  /// keeps one decimal place otherwise.
  String _formatSqft(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  Widget _buildInfoTile(_InfoItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.ctaGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(item.icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.value,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  // Was 1 line — long values (Property Condition options
                  // like "Under Construction", or a long Property Type
                  // name) silently clipped to an ellipsis within this
                  // tile's fixed width. 2 lines costs nothing for every
                  // other tile's short values (a Text widget that fits on
                  // one line never grows to use a second), so this is a
                  // safe blanket fix rather than a per-tile special case.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // An empty label (e.g. the Property Condition tile, on
                // request) skips the caption entirely rather than leaving
                // behind a blank line of its own height.
                if (item.label.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    item.label,
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // EXPANDABLE DESCRIPTION ("About Property")
  // ===========================================================================

  Widget _buildExpandableDescription(dynamic property) {
    final String description = property.description as String;
    final TextStyle descriptionStyle = AppTextStyles.caption.copyWith(
      fontSize: 13,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textHint.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool needsReadMore = (TextPainter(
            text: TextSpan(text: description, style: descriptionStyle),
            maxLines: 3,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: constraints.maxWidth)).didExceedMaxLines;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'About Property',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Text(
                  description,
                  style: descriptionStyle,
                  maxLines: _isDescriptionExpanded ? null : 3,
                  overflow: _isDescriptionExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              ),
              if (needsReadMore) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isDescriptionExpanded = !_isDescriptionExpanded;
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _isDescriptionExpanded ? 'Read less ‹' : 'Read more ›',
                      key: ValueKey<bool>(_isDescriptionExpanded),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // ADDITIONAL DETAILS (properties.metadata)
  // ===========================================================================

  /// Surfaces the long-tail wizard fields already written into
  /// `properties.metadata` (RERA, facing, legal approvals, utilities, pricing
  /// overflow, contact preferences) that have no dedicated PropertyModel
  /// column/field. Each group is omitted entirely when none of its fields are
  /// present — same "hide empty group" rule the portal's
  /// renderAdditionalDetails/renderExtendedDetails use.
  Widget _buildAdditionalDetailsSection(
    dynamic property, {
    Map<String, List<_InfoItem>> tiles = const {},
    int tileColumns = 2,
  }) {
    final Map<String, dynamic> meta =
        (property.metadata as Map<String, dynamic>?) ?? const {};
    if (meta.isEmpty && tiles.values.every((t) => t.isEmpty)) {
      return const SizedBox.shrink();
    }

    String? str(String key) {
      final v = meta[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    bool isTrue(String key) => meta[key] == true;

    // `metadata.buildingInventory` (commercial's Condition/Amenities steps —
    // condition_step.dart's Building Condition card, amenities_step.dart's
    // Building Facilities card) is a nested object, written unconditionally
    // on every commercial save (property_service.dart) but never read by
    // `str`/`isTrue`/`strList` above, which only ever look at flat top-level
    // keys. That gap was hiding Building Age, building Ownership Type,
    // Working Days, Building Working Hours, Lift Count, Service Lift Count,
    // Security Guards, Total Car/Bike Parking and Common Area Maintenance
    // Charges all at once — none of them reachable by any existing row.
    final Map<String, dynamic> buildingInventory =
        (meta['buildingInventory'] as Map<String, dynamic>?) ?? const {};
    String? invStr(String key) {
      final v = buildingInventory[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    List<String> strList(String key) {
      final v = meta[key];
      if (v is List) {
        return v
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      return const [];
    }

    // The labels of every option in [options] whose own boolean metadata key
    // (`option.id`) is true — for the PG amenity/safety/rule checkbox groups,
    // which each write one bool per option rather than a single list.
    List<String> selectedLabels(List<ListingOption> options) => [
      for (final o in options)
        if (isTrue(o.id)) o.label,
    ];

    // `metadata.floorWiseRoomDetails` is `{floorNumber, totalRooms, rooms:
    // [{roomNumber, roomType}]}[]`, written for PG/co-living listings
    // (post_property_provider.dart's floorWiseRoomDetails). It is a list of
    // objects, so it doesn't fit the `str`/`isTrue`/`strList` scalar helpers
    // above — parsed separately here into one row per floor.
    final List<_DetailRow> roomDetailRows = [];
    final dynamic floorWiseRoomDetails = meta['floorWiseRoomDetails'];
    // Combined count across every floor — the wizard itself shows this live
    // (`PostPropertyProvider.totalRoomsAcrossFloors`, read-only derived box
    // in property_dimensions_step.dart's PG step), but nothing persisted it
    // under its own key, so the detail page had only the per-floor rows
    // below and no single total.
    if (floorWiseRoomDetails is List && floorWiseRoomDetails.isNotEmpty) {
      int totalRoomsSum = 0;
      for (final floor in floorWiseRoomDetails) {
        if (floor is! Map) continue;
        totalRoomsSum +=
            int.tryParse(floor['totalRooms']?.toString() ?? '') ?? 0;
      }
      if (totalRoomsSum > 0) {
        roomDetailRows.add(_DetailRow('Total Room(s)', '$totalRoomsSum'));
      }
    }
    if (floorWiseRoomDetails is List) {
      for (final floor in floorWiseRoomDetails) {
        if (floor is! Map) continue;
        final floorNumber = floor['floorNumber']?.toString();
        final totalRooms = floor['totalRooms']?.toString();
        final rooms = floor['rooms'];

        String roomTypeSummary = '';
        if (rooms is List && rooms.isNotEmpty) {
          final Map<String, int> typeCounts = {};
          for (final room in rooms) {
            final roomType = room is Map ? room['roomType']?.toString() : null;
            if (roomType == null || roomType.trim().isEmpty) continue;
            typeCounts[roomType] = (typeCounts[roomType] ?? 0) + 1;
          }
          roomTypeSummary = typeCounts.entries
              .map((e) => '${e.value} ${e.key}')
              .join(', ');
        }

        final String value = [
          if (totalRooms != null && totalRooms.trim().isNotEmpty)
            '$totalRooms rooms',
          if (roomTypeSummary.isNotEmpty) roomTypeSummary,
        ].join(' — ');

        if (value.isNotEmpty) {
          roomDetailRows.add(
            _DetailRow(
              floorNumber != null && floorNumber.trim().isNotEmpty
                  ? 'Floor $floorNumber'
                  : 'Floor',
              value,
            ),
          );
        }
      }
    }

    final List<_DetailGroup> legacyGroups = [
      _DetailGroup('Room Details', roomDetailRows),
      _DetailGroup('Additional Features', [
        if (strList('retailFeatures').isNotEmpty)
          _DetailRow(
            'Retail & Warehouse Features',
            strList('retailFeatures').join(', '),
          ),
        if (strList('warehouseFeatures').isNotEmpty)
          _DetailRow(
            'Warehouse Features',
            strList('warehouseFeatures').join(', '),
          ),
        if (strList('additionalFeatures').isNotEmpty)
          _DetailRow(
            'Additional Features',
            strList('additionalFeatures').join(', '),
          ),
      ]),
      _DetailGroup('Condition & Availability', [
        // For residential, this is the exact same value as the Possession
        // tile above (both read `metadata.propertyCondition`) — showing
        // both in the same place (now Dimensions & Layout, since the tile
        // moved there too) would just be the identical "Resale"/etc. value
        // twice. The tile is the more prominent of the two, so this row is
        // suppressed for residential specifically; every other category is
        // unchanged (plain 'Condition' label, as before).
        if (str('propertyCondition') != null &&
            property.category != 'residential')
          _DetailRow('Condition', str('propertyCondition')!),
        if (str('constructionAge') != null)
          _DetailRow('Construction Age', str('constructionAge')!),
        if (str('availabilityStatus') != null)
          _DetailRow('Availability', str('availabilityStatus')!),
        if (str('facing') != null) _DetailRow('Facing', str('facing')!),
        if (strList('availableItems').isNotEmpty)
          _DetailRow('Available Items', strList('availableItems').join(', ')),
      ]),
      _DetailGroup('Utilities & Infrastructure', [
        if (str('electricityBackup') != null)
          _DetailRow('Electricity Backup', str('electricityBackup')!),
        if (str('waterAvailability') != null)
          _DetailRow('Water Availability', str('waterAvailability')!),
        if (str('numberOfLifts') != null)
          _DetailRow('Lifts', str('numberOfLifts')!),
        if (str('openParking') != null)
          _DetailRow('Open Parking', str('openParking')!),
        if (isTrue('gasPipeline')) _DetailRow('Gas Pipeline', 'Yes'),
        if (isTrue('internetAvailability')) _DetailRow('Internet', 'Available'),
        if (isTrue('solarBackup')) _DetailRow('Solar Backup', 'Yes'),
        if (isTrue('guardRoom')) _DetailRow('Guard Room', 'Yes'),
      ]),
      // Mirrors the portal's renderExtendedDetails "Legal & Society" group
      // (PropertyDetails.tsx) — every field is read straight off the same
      // `properties.metadata` blob the website reads, so listings created on
      // the website (which collects all of these) display correctly here
      // too, not just app-created ones.
      _DetailGroup('Legal & Society', [
        if (isTrue('reraRegistered'))
          _DetailRow('RERA Registered', str('reraNumber') ?? 'Yes'),
        if (isTrue('saleDeed')) _DetailRow('Sale Deed', 'Available'),
        if (isTrue('registryCopy')) _DetailRow('Registry Copy', 'Available'),
        if (isTrue('registeredAgreement'))
          _DetailRow('Registered Agreement', 'Yes'),
        if (isTrue('unregisteredAgreement'))
          _DetailRow('Unregistered Agreement', 'Yes'),
        if (isTrue('nocAvailable')) _DetailRow('NOC', 'Available'),
        if (isTrue('encumbranceFree')) _DetailRow('Encumbrance Free', 'Yes'),
        if (isTrue('propertyApproved')) _DetailRow('Property Approved', 'Yes'),
        if (isTrue('approvedByAuthority'))
          _DetailRow('Approved By Authority', 'Yes'),
        if (isTrue('khataAvailable')) _DetailRow('Khata Available', 'Yes'),
        if (isTrue('pattaAvailable')) _DetailRow('Patta Available', 'Yes'),
        if (isTrue('jamabandiAvailable'))
          _DetailRow('Jamabandi Available', 'Yes'),
        if (isTrue('mutationAvailable'))
          _DetailRow('Mutation Available', 'Yes'),
        if (isTrue('ocCertificate')) _DetailRow('Occupancy Certificate', 'Yes'),
        if (isTrue('completionCertificate'))
          _DetailRow('Completion Certificate', 'Yes'),
        if (isTrue('buildingApproval')) _DetailRow('Building Approval', 'Yes'),
        if (isTrue('taxReceipt')) _DetailRow('Tax Receipt', 'Available'),
        if (isTrue('propertyTaxPaid')) _DetailRow('Property Tax Paid', 'Yes'),
        if (isTrue('courtCasePending')) _DetailRow('Court Case Pending', 'Yes'),
        if (isTrue('loanApproved') || isTrue('bankLoanApproved'))
          _DetailRow('Bank Loan Approved', 'Yes'),
        if (strList('approvedByBanks').isNotEmpty)
          _DetailRow(
            'Approved By Banks',
            strList('approvedByBanks').join(', '),
          ),
        // Flutter's own Commercial Legal step only ever sets `fireNoc`/
        // `tradeLicenseAvailable` (legal_details_step.dart) — never the
        // `fireLicense`/`tradeLicense` siblings this row reads. The portal's
        // checkbox dual-writes both on every change (LegalDetailsStep.tsx),
        // so a portal-created listing matched this read already; an
        // app-created one never did. OR-read both, same precedent as
        // `loanApproved || bankLoanApproved` just above.
        if (isTrue('fireLicense') || isTrue('fireNoc'))
          _DetailRow('Fire NOC / License', 'Yes'),
        if (isTrue('tradeLicense') || isTrue('tradeLicenseAvailable'))
          _DetailRow('Trade License', 'Yes'),
        if (isTrue('foodLicense')) _DetailRow('Food License', 'Yes'),
        if (isTrue('pollutionClearance'))
          _DetailRow('Pollution Clearance', 'Yes'),
        if (isTrue('industrialApproval'))
          _DetailRow('Industrial Approval', 'Yes'),
        if (isTrue('hostelLicense')) _DetailRow('Hostel License', 'Yes'),
        if (isTrue('dispute')) _DetailRow('Under Dispute', 'Yes'),
        if (str('registrationTitle') != null)
          _DetailRow('Registration Title', str('registrationTitle')!),
        if (str('mutation') != null) _DetailRow('Mutation', str('mutation')!),
        if (str('ownershipType') != null)
          _DetailRow('Ownership Type', str('ownershipType')!),
        if (str('ownerName') != null)
          _DetailRow('Owner Name', str('ownerName')!),
        if (isTrue('ownerLiveInSociety'))
          _DetailRow('Owner Lives In Society', 'Yes'),
        if (isTrue('registrationRequired'))
          _DetailRow('Registration Required', 'Yes'),
      ]),
      // Mirrors the portal's "Financial & Pricing" group.
      _DetailGroup('Financial & Pricing', [
        if (str('financeStatus') != null)
          _DetailRow('Finance Status', str('financeStatus')!),
        if (str('priceType') != null)
          _DetailRow('Price Type', str('priceType')!),
        if (isTrue('priceNegotiable')) _DetailRow('Price Negotiable', 'Yes'),
        if (str('otherTax') != null) _DetailRow('Other Tax', str('otherTax')!),
        if (str('societyMaintenance') != null)
          _DetailRow('Society Maintenance', str('societyMaintenance')!),
        // Distinct from both neighbors above — the Pricing step's
        // "Society Charges (Monthly)" field for apartment Rent/Lease
        // listings (pricing_step.dart, `_isApartmentRental`). Portal renders
        // all three as separate rows (PropertyDetails.tsx:1421-1423); this
        // one had no read site at all, so it saved fine but never displayed.
        if (str('societyCharges') != null)
          _DetailRow('Society Charges', str('societyCharges')!),
        if (str('maintenanceCharges') != null)
          _DetailRow('Maintenance Charges', str('maintenanceCharges')!),
        if (str('securityDeposit') != null)
          _DetailRow('Security Deposit', str('securityDeposit')!),
        if (str('bookingAmount') != null)
          _DetailRow('Booking Amount', str('bookingAmount')!),
        if (str('tokenAmount') != null)
          _DetailRow('Token Amount', str('tokenAmount')!),
        if (str('lockInPeriod') != null)
          _DetailRow('Lock-in Period', str('lockInPeriod')!),
        if (str('brokerage') != null)
          _DetailRow('Brokerage', str('brokerage')!),
        if (str('brokerageType') != null)
          _DetailRow('Brokerage Type', str('brokerageType')!),
        if (isTrue('taxGovtChargesIncluded'))
          _DetailRow('Tax/Govt Charges Included', 'Yes'),
        if (isTrue('allInclusivePriceToggle'))
          _DetailRow('All Inclusive Price', 'Yes'),
        // `loanAvailability` is a real bool (property_service.dart writes it
        // unconditionally — no UI anywhere collects it, "explicit product
        // decision" per pricing_step.dart's own comment, so it is always
        // `false` for an app-created listing). Reading it with `str()`
        // stringified that bool and rendered "Loan Availability: false" on
        // literally every listing — the exact unasked-default this page's
        // boolean rows are otherwise careful to omit. `isTrue()` matches the
        // pattern every other boolean row here already uses.
        if (isTrue('loanAvailability')) _DetailRow('Loan Availability', 'Yes'),
        if (str('expectedAppreciation') != null)
          _DetailRow('Expected Appreciation', str('expectedAppreciation')!),
        if (str('rentalYield') != null)
          _DetailRow('Rental Yield', str('rentalYield')!),
        if (str('expectedPrice') != null)
          _DetailRow(
            // Matches the wizard's own per-intent label (pricing_step.dart's
            // `_askingPriceLabel`) — the static "Expected Price" caption was
            // the wrong word for Lease (every category) and, for Others
            // specifically, also wrong for Rent (wizard says "Total Asking
            // Price"). PG shares Land's "per year" wording for lease.
            // Residential/Commercial's own Rent label hasn't been reported
            // as wrong, so it's untouched — only Others' Rent case changes.
            property.category == 'land'
                ? switch (property.propertyType) {
                    'rent' => 'Rent Amount per Month',
                    'lease' => 'Lease Amount per Year',
                    _ => 'Asking Price',
                  }
                : property.propertyType == 'lease'
                ? (property.category == 'pg_coliving'
                      ? 'Lease Amount per Year'
                      : 'Lease Amount')
                : (property.category == 'others' &&
                      property.propertyType == 'rent')
                ? 'Total Asking Price'
                : 'Expected Price',
            str('expectedPrice')!,
          ),
        if (isTrue('gstApplicable')) _DetailRow('GST Applicable', 'Yes'),
        // Commercial "Current Business" card (amenities_step.dart) — saved,
        // never shown.
        if (isTrue('currentBusinessRunning'))
          _DetailRow('Current Business Running', 'Yes'),
        if (str('businessType') != null)
          _DetailRow('Business Type', str('businessType')!),
        // Commercial Investment Details (sell) / Lease Terms (lease) —
        // pricing_step.dart. Portal shows these via its generic metadata
        // catch-all with auto-generated labels; reused verbatim here.
        if (str('roiEstimate') != null)
          _DetailRow('Roi Estimate', str('roiEstimate')!),
        if (str('currentRentalIncome') != null)
          _DetailRow('Current Rental Income', str('currentRentalIncome')!),
        if (isTrue('tenantOccupied')) _DetailRow('Tenant Occupied', 'Yes'),
        if (isTrue('leaseRunning')) _DetailRow('Lease Running', 'Yes'),
        if (str('leaseDuration') != null || str('minRentalDuration') != null)
          _DetailRow(
            'Lease Duration',
            (str('leaseDuration') ?? str('minRentalDuration'))!,
          ),
        if (str('rentEscalation') != null ||
            str('leaseEscalationPercent') != null)
          _DetailRow(
            'Rent Escalation',
            (str('rentEscalation') ?? str('leaseEscalationPercent'))!,
          ),
        if (str('camCharges') != null)
          _DetailRow('CAM Charges', str('camCharges')!),
        if (str('fitOutPeriod') != null)
          _DetailRow('Fit-out Period', str('fitOutPeriod')!),
        // PG Rent Details (pricing_step.dart) — two genuinely distinct
        // fields, not one under two names.
        if (str('monthlyRentPerBed') != null)
          _DetailRow('Monthly Rent / Bed', str('monthlyRentPerBed')!),
        if (str('monthlyRentPerRoom') != null)
          _DetailRow('Monthly Rent / Room', str('monthlyRentPerRoom')!),
        // PG extra charges — distinct from the `pgFoodAvailable`/
        // `pgLaundryAvailable` availability flags already shown above;
        // these are the actual amounts.
        if (str('foodCharges') != null)
          _DetailRow('Food Charges', str('foodCharges')!),
        if (str('laundryCharges') != null)
          _DetailRow('Laundry Charges', str('laundryCharges')!),
        if (isTrue('housekeepingIncluded'))
          _DetailRow('Housekeeping Included', 'Yes'),
        if (isTrue('companyTieUp')) _DetailRow('Company Tie-up', 'Yes'),
        // PG Sale Details / PG Lease Details cards (pricing_step.dart).
        if (str('totalSalePrice') != null)
          _DetailRow('Total Sale Price', str('totalSalePrice')!),
        if (str('occupancyRate') != null)
          _DetailRow('Occupancy Rate', str('occupancyRate')!),
        if (isTrue('businessIncluded')) _DetailRow('Business Included', 'Yes'),
        if (isTrue('furnitureIncluded'))
          _DetailRow('Furniture Included', 'Yes'),
        if (isTrue('brandFranchiseIncluded'))
          _DetailRow('Brand / Franchise Included', 'Yes'),
        if (isTrue('existingStaffIncluded'))
          _DetailRow('Existing Staff Included', 'Yes'),
        if (isTrue('managementTransfer'))
          _DetailRow('Management Transfer', 'Yes'),
        if (isTrue('renewableLease')) _DetailRow('Renewable Lease', 'Yes'),
        if (isTrue('franchiseOperationAllowed'))
          _DetailRow('Franchise Operation Allowed', 'Yes'),
      ]),
      // Mirrors the portal's "Construction & Land" group.
      _DetailGroup('Construction & Land', [
        if (str('projectStatus') != null)
          _DetailRow('Project Status', str('projectStatus')!),
        if (str('projectName') != null)
          _DetailRow('Project Name', str('projectName')!),
        if (str('builderName') != null)
          _DetailRow('Builder Name', str('builderName')!),
        if (str('totalFlats') != null)
          _DetailRow('Total Flats', str('totalFlats')!),
        if (str('plotArea') != null)
          _DetailRow(
            'Plot Area',
            [
              str('plotArea'),
              // Was the raw stored unit id verbatim (e.g. "2000 sq_yd") —
              // property_dimensions_step.dart's commercial Plot Area field
              // uses its own local unit list (`kPlotAreaUnits`), whose
              // `sq_yd` id has no match in the shared `kAreaUnitLabels` map
              // (which instead keys on `sq_yards`), so even the one real
              // match (`plotAreaUnitLabelFallback`) is needed for full
              // coverage.
              if (str('plotAreaUnit') != null)
                kAreaUnitLabels[str('plotAreaUnit')] ??
                    _kPlotAreaUnitLabelFallback[str('plotAreaUnit')] ??
                    str('plotAreaUnit'),
            ].whereType<String>().join(' '),
          ),
        // `superBuiltUpArea` (commercial Dimensions step) mirrors its value
        // into the typed `area` column too (same onChanged call also fires
        // `p.setArea`), so the number already shows via the generic "Area"
        // tile above — just never under its own name, and the metadata
        // copy of the figure itself had no read site at all. Paired with
        // `property.areaUnit` since the wizard field shares that same unit
        // control rather than having one of its own.
        if (str('superBuiltUpArea') != null)
          _DetailRow(
            'Super Built-up Area',
            '${str('superBuiltUpArea')} ${property.areaUnit == null ? '' : (kAreaUnitLabels[property.areaUnit] ?? property.areaUnit)}'
                .trim(),
          ),
        if (str('spaceDetails') != null)
          _DetailRow('Space Details', str('spaceDetails')!),
        if (str('areaPerFloor') != null)
          _DetailRow('Area Per Floor', str('areaPerFloor')!),
        if (str('landType') != null) _DetailRow('Land Type', str('landType')!),
        if (str('boundary') != null) _DetailRow('Boundary', str('boundary')!),
      ]),
      // Mirrors the wizard's own commercial "Building Facilities"/"Building
      // Condition" cards (amenities_step.dart, condition_step.dart) — every
      // field here lives in `metadata.buildingInventory`, which previously
      // had no reader anywhere on this page (see `invStr` above). Distinct
      // labels from any similarly-named existing row on purpose (e.g.
      // "Building Ownership Type" vs. land's plain "Ownership Type",
      // "Lift Count" vs. the unrelated residential/land "Lifts" row,
      // "Security Guards" vs. the unrelated boolean "Guard Room" row) so
      // this addition can't collide with or reroute something already
      // working for a different category.
      _DetailGroup('Building Facilities', [
        if (invStr('buildingAge') != null)
          _DetailRow('Building Age', invStr('buildingAge')!),
        if (invStr('ownershipTypeBuilding') != null)
          _DetailRow(
            'Building Ownership Type',
            invStr('ownershipTypeBuilding')!,
          ),
        if (invStr('workingDays') != null)
          _DetailRow('Working Days', invStr('workingDays')!),
        if (invStr('buildingWorkingHours') != null)
          _DetailRow('Building Working Hours', invStr('buildingWorkingHours')!),
        if (invStr('liftCount') != null)
          _DetailRow('Lift Count', invStr('liftCount')!),
        if (invStr('serviceLiftCount') != null)
          _DetailRow('Service Lift Count', invStr('serviceLiftCount')!),
        if (invStr('securityGuards') != null)
          _DetailRow('Security Guards', invStr('securityGuards')!),
        if (invStr('totalCarParking') != null)
          _DetailRow('Total Car Parking', invStr('totalCarParking')!),
        if (invStr('totalBikeParking') != null)
          _DetailRow('Total Bike Parking', invStr('totalBikeParking')!),
        if (invStr('commonAreaMaintenanceCharges') != null)
          _DetailRow(
            'Common Area Maintenance Charges',
            invStr('commonAreaMaintenanceCharges')!,
          ),
      ]),
      // Mirrors the Dimensions step's own "Land Specification" card
      // (property_dimensions_step.dart:400-499) — these bag keys saved
      // correctly but had no read site anywhere on this page.
      _DetailGroup('Land Specification', [
        // Portal's own labels (PropertyDetails.tsx's renderLandSpecifications,
        // which groups these alongside front/back/right/left the same way).
        if (str('landSubtype') != null)
          _DetailRow('Land Sub-type', str('landSubtype')!),
        if (str('landUseMasterPlan') != null)
          _DetailRow('Master Plan Zoning', str('landUseMasterPlan')!),
        for (final side in const ['front', 'back', 'right', 'left'])
          if (str(side) != null)
            _DetailRow(
              '${side[0].toUpperCase()}${side.substring(1)}',
              [str(side), str('${side}Unit')].whereType<String>().join(' '),
            ),
        if (str('surveyNumber') != null)
          _DetailRow('Khasra Number', str('surveyNumber')!),
        if (str('fsiFarAllowed') != null)
          _DetailRow('FSI/FAR Allowed', str('fsiFarAllowed')!),
        if (str('floorAllowed') != null)
          _DetailRow('Floor Allowed', str('floorAllowed')!),
        if (str('heightRestriction') != null)
          _DetailRow(
            'Height Restriction',
            [
              str('heightRestriction'),
              str('heightRestrictionUnit'),
            ].whereType<String>().join(' '),
          ),
        if (str('soilType') != null) _DetailRow('Soil Type', str('soilType')!),
      ]),
      // The app's own PG wizard (amenities_step.dart's PG & Co-Living
      // Amenities card) writes each room amenity / safety-and-security flag
      // as its own boolean metadata key, common-area amenities as the
      // `pgAmenities` list, and tenant rules as their own booleans — none of
      // which overlap with the portal-mirrored `pgFoodAvailable`-style keys
      // in "PG Specific Details" below, so a PG listing's actual selections
      // never showed up anywhere on this screen.
      //
      // Gated behind category == PG: these bag keys live in a flat map
      // shared by every category (see PropertyService._buildMetadata), so a
      // listing saved before that fix, or any other stray data, could still
      // carry PG keys under a non-PG category — this keeps them from ever
      // rendering on a Land/Residential/Commercial/Other listing's page.
      _DetailGroup('PG Amenities', [
        if (property.category == 'pg_coliving') ...[
          if (selectedLabels(kPgRoomAmenities).isNotEmpty)
            _DetailRow(
              'Room Amenities',
              selectedLabels(kPgRoomAmenities).join(', '),
            ),
          if (strList('pgAmenities').isNotEmpty)
            _DetailRow(
              'Common Area Amenities',
              strList('pgAmenities').join(', '),
            ),
          if (selectedLabels(kPgSafetyAndSecurity).isNotEmpty)
            _DetailRow(
              'Safety & Security',
              selectedLabels(kPgSafetyAndSecurity).join(', '),
            ),
          if (selectedLabels(kPgTenantRules).isNotEmpty)
            _DetailRow(
              'Tenant Rules',
              selectedLabels(kPgTenantRules).join(', '),
            ),
        ],
      ]),
      // Same gap as "PG Amenities" above — the app's own PG wizard
      // (condition_step.dart's Food & Services / Housekeeping cards) writes
      // these keys, none of which the portal-mirrored group below reads.
      // Same category gate as "PG Amenities" above, for the same reason.
      _DetailGroup('Food & Services', [
        if (property.category == 'pg_coliving') ...[
          if (isTrue('vegFoodPg')) _DetailRow('Veg Food Available', 'Yes'),
          if (isTrue('nonVegFoodPg'))
            _DetailRow('Non-Veg Food Available', 'Yes'),
          if (isTrue('selfCookingAllowed'))
            _DetailRow('Self-Cooking Allowed', 'Yes'),
          if (isTrue('sharedKitchen')) _DetailRow('Shared Kitchen', 'Yes'),
          if (strList('mealsIncluded').isNotEmpty)
            _DetailRow('Meals Included', strList('mealsIncluded').join(', ')),
          if (strList('breakfastItems').isNotEmpty)
            _DetailRow('Breakfast Items', strList('breakfastItems').join(', ')),
          if (strList('lunchItems').isNotEmpty)
            _DetailRow('Lunch Items', strList('lunchItems').join(', ')),
          if (strList('dinnerItems').isNotEmpty)
            _DetailRow('Dinner Items', strList('dinnerItems').join(', ')),
          if (strList('teaSnacksItems').isNotEmpty)
            _DetailRow(
              'Tea / Snacks Items',
              strList('teaSnacksItems').join(', '),
            ),
          if (isTrue('laundryService')) _DetailRow('Laundry Service', 'Yes'),
          if (isTrue('cleaningService')) _DetailRow('Cleaning Service', 'Yes'),
          if (isTrue('dailyCleaning')) _DetailRow('Daily Cleaning', 'Yes'),
          if (str('roomCleaningFrequency') != null)
            _DetailRow(
              'Room Cleaning Frequency',
              str('roomCleaningFrequency')!,
            ),
          if (str('linenChangeFrequency') != null)
            _DetailRow('Linen Change Frequency', str('linenChangeFrequency')!),
        ],
      ]),
      // Mirrors the portal's "PG Specific Details" group in
      // PropertyDetails.tsx exactly — same metadata keys, same labels. These
      // keys have no input anywhere in the app's own PG wizard, so this group
      // only ever populates for web-created PG listings; it's kept as-is
      // (rather than removed) so those still display correctly.
      _DetailGroup('PG Specific Details', [
        // Defense-in-depth, matching the "PG Amenities"/"Food & Services"
        // groups further up: these bag keys live in the flat map shared by
        // every category, and until just now 4 of them (pgPropertyType,
        // buildingType, pgPropertyName, propertyStatus) weren't in
        // `_pgOnlyMetadataKeys`, so a listing switched PG → Land/Residential
        // /Commercial/Other before publishing could carry e.g. "Property
        // Status" into a non-PG listing's saved metadata. The save-side fix
        // stops this for anything saved from now on; this category check
        // stops it from showing on a listing that was already saved that
        // way before the fix.
        if (property.category == 'pg_coliving') ...[
          // Collected on Basic Info (basic_info_step.dart), re-bucketed
          // there via `_kRowLabelStep` below — saved, never shown until now.
          if (str('pgPropertyName') != null)
            _DetailRow('PG Name', str('pgPropertyName')!),
          if (str('buildingType') != null)
            _DetailRow('Building Type', str('buildingType')!),
          if (str('propertyStatus') != null)
            _DetailRow('Property Status', str('propertyStatus')!),
          // Collected on Legal (legal_details_step.dart) as one field that
          // dual-writes both keys; portal explicitly ORs them to avoid a
          // double row (PropertyDetails.tsx comment) — same here.
          if (str('quietHours') != null || str('pgGateClosingTime') != null)
            _DetailRow(
              'Quiet Hours / Gate Closing Time',
              (str('quietHours') ?? str('pgGateClosingTime'))!,
            ),
          if (str('pgSharingType') != null)
            _DetailRow('Sharing Type', str('pgSharingType')!),
          if (str('pgTenantType') != null)
            _DetailRow('Tenant Type', str('pgTenantType')!),
          if (str('pgPropertyType') != null)
            _DetailRow('PG Property Type', str('pgPropertyType')!),
          if (isTrue('pgFoodAvailable')) _DetailRow('Food Available', 'Yes'),
          if (isTrue('pgWifiAvailable')) _DetailRow('WiFi Available', 'Yes'),
          if (isTrue('pgLaundryAvailable'))
            _DetailRow('Laundry Available', 'Yes'),
          if (isTrue('pgAcAvailable')) _DetailRow('AC Available', 'Yes'),
          if (isTrue('pgCleaningAvailable'))
            _DetailRow('Cleaning Available', 'Yes'),
          if (isTrue('pgSecurityAvailable'))
            _DetailRow('Security Available', 'Yes'),
          if (isTrue('pgPowerBackupAvailable'))
            _DetailRow('Power Backup Available', 'Yes'),
          if (isTrue('pgLiftAvailable')) _DetailRow('Lift Available', 'Yes'),
          if (isTrue('pgParkingAvailable'))
            _DetailRow('Parking Available', 'Yes'),
          if (strList('pgMealTypes').isNotEmpty)
            _DetailRow('Meal Types', strList('pgMealTypes').join(', ')),
          if (str('pgNoticePeriod') != null)
            _DetailRow('Notice Period', str('pgNoticePeriod')!),
          if (str('pgLockInPeriod') != null)
            _DetailRow('Lock-in Period', str('pgLockInPeriod')!),
          if (str('pgVisitorPolicy') != null)
            _DetailRow('Visitor Policy', str('pgVisitorPolicy')!),
        ],
      ]),
      // Each preference is its own boolean metadata key (familyAllowed,
      // bachelorAllowed, ...) — see `AmenitiesStep`'s "Tenant Preferences"
      // card, which writes them through the generic bool bag rather than a
      // list, same as the PG amenity/safety groups above.
      _DetailGroup('Tenant Preferences', [
        if (selectedLabels(kResidentialTenantPreferences).isNotEmpty)
          _DetailRow(
            'Preferred Tenants',
            selectedLabels(kResidentialTenantPreferences).join(', '),
          ),
      ]),
      _DetailGroup('Contact Preferences', [
        if (str('contactName') != null)
          _DetailRow('Contact Name', str('contactName')!),
        // Same source/shape as `_contactEmail` right below — a listing-
        // specific `property_contact_details.contact_phone` override,
        // already fetched for the Call button's fallback chain but never
        // shown as its own row anywhere on this page. Unlike email, this
        // one isn't inquiry-gated (every viewer can already see/call it via
        // the Call button), so no visibility check beyond non-empty is
        // needed.
        if (_contactPhone != null && _contactPhone!.isNotEmpty)
          _DetailRow('Phone Number', _contactPhone!),
        // Not in `metadata` — a listing-specific `property_contact_details`
        // row, RLS-gated to the owner/admin/an approved inquirer (see
        // `PropertyService.getPropertyDetail`), so this is null rather than
        // absent from the map for most viewers.
        if (_contactEmail != null && _contactEmail!.isNotEmpty)
          _DetailRow('Email', _contactEmail!),
        if (str('whatsappNumber') != null)
          _DetailRow('WhatsApp Number', str('whatsappNumber')!),
        if (str('bestTimeToCall') != null)
          _DetailRow('Best Time To Call', str('bestTimeToCall')!),
        // PG-specific contact override (media_contact_step.dart, `isPg`).
        if (str('ownerManagerName') != null)
          _DetailRow('Manager / Owner Name', str('ownerManagerName')!),
        if (str('alternateNumber') != null)
          _DetailRow('Alternate Number', str('alternateNumber')!),
      ]),
    ];

    // Re-bucket every row under the listing-form step that collects it, so
    // the page reads in the order the seller filled the form in: all area
    // items under Dimensions & Layout, all price items under Pricing & Terms,
    // amenities and facilities under Amenities & Facilities, and so on. A
    // row's own label wins over its old group where the two disagree (e.g.
    // 'Facing' sat in Condition but is a Dimensions field).
    final Map<String, List<_DetailRow>> rowsByStep = {
      for (final step in _kListingStepTitles) step: <_DetailRow>[],
    };
    for (final group in legacyGroups) {
      for (final row in group.rows) {
        final step =
            _kRowLabelStep[row.label] ??
            _kLegacyGroupStep[group.title] ??
            _kStepAmenities;
        rowsByStep[step]!.add(row);
      }
    }

    // This step's own data (utilities/infrastructure booleans, Preferred
    // Tenants) is NOT the amenity checklist the wizard's Amenities step
    // collects for Society/Flat/Parking features — that one already has
    // its own display, the icon-row section below the map
    // (`_buildAmenitiesSection`). Sharing the title "Amenities &
    // Facilities" with that section read as the same thing shown twice.
    // Renamed here for every category except PG, where this step's
    // content genuinely is the amenity checklist (PG Amenities/PG
    // Specific Details), so "Amenities & Facilities" stays accurate there.
    String stepTitle(String step) {
      if (step == _kStepAmenities && property.category != 'pg_coliving') {
        return 'Utilities & Preferences';
      }
      return step;
    }

    final List<_DetailGroup> groups = [
      for (final step in _kListingStepTitles)
        _DetailGroup(
          stepTitle(step),
          rowsByStep[step]!,
          tiles[step] ?? const [],
        ),
    ].where((g) => g.rows.isNotEmpty || g.tiles.isNotEmpty).toList();

    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Property Information',
          style: AppTextStyles.heading3.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 14),
        for (final group in groups) ...[
          _buildDetailGroupHeader(group.title),
          const SizedBox(height: 8),
          if (!_collapsedDetailGroups.contains(group.title)) ...[
            if (group.tiles.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: group.tiles.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: tileColumns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                itemBuilder: (BuildContext context, int index) =>
                    _buildInfoTile(group.tiles[index]),
              ),
            if (group.tiles.isNotEmpty && group.rows.isNotEmpty)
              const SizedBox(height: 12),
            if (group.rows.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  // Stretch so a list-style row (label above its value) spans the
                  // card and starts at the same left edge as the short rows.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < group.rows.length; i++) ...[
                      if (i > 0) const Divider(height: 20),
                      _buildDetailRow(group.rows[i]),
                    ],
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  /// A group's title bar — icon medallion, bold title, and a chevron that
  /// collapses/expands its rows. Matches the Compare Properties screen's
  /// section-header treatment (`compare_properties_screen.dart`'s
  /// `_buildSectionBanner`), so the two screens read as the same design
  /// system rather than two different conventions.
  Widget _buildDetailGroupHeader(String title) {
    final bool collapsed = _collapsedDetailGroups.contains(title);
    return GestureDetector(
      onTap: () => _toggleDetailGroup(title),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.14),
              AppColors.primary.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _detailGroupIcon(title),
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            AnimatedRotation(
              turns: collapsed ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 22,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _detailGroupIcon(String title) {
    switch (title) {
      case _kStepBasic:
        return Icons.edit_note_rounded;
      case _kStepDimensions:
        return Icons.straighten_rounded;
      case _kStepCondition:
        return Icons.fact_check_outlined;
      case _kStepAmenities:
        return Icons.checklist_rounded;
      case 'Utilities & Preferences':
        return Icons.bolt_outlined;
      case _kStepLegal:
        return Icons.gavel_outlined;
      case _kStepPricing:
        return Icons.currency_rupee_rounded;
      case _kStepContact:
        return Icons.contact_phone_outlined;
      case 'Room Details':
        return Icons.meeting_room_outlined;
      case 'Additional Features':
        return Icons.add_circle_outline;
      case 'Condition & Availability':
        return Icons.fact_check_outlined;
      case 'Utilities & Infrastructure':
        return Icons.bolt_outlined;
      case 'Legal & Society':
        return Icons.gavel_outlined;
      case 'Financial & Pricing':
        return Icons.currency_rupee_rounded;
      case 'Construction & Land':
        return Icons.apartment_outlined;
      case 'PG Amenities':
        return Icons.checklist_rounded;
      case 'Food & Services':
        return Icons.restaurant_outlined;
      case 'PG Specific Details':
        return Icons.house_siding_outlined;
      case 'Contact Preferences':
        return Icons.contact_phone_outlined;
      default:
        return Icons.info_outline;
    }
  }

  /// One row of a detail group. A short value (e.g. "propcid", "New") sits
  /// beside its label, same as before. A long, list-style value (built
  /// elsewhere via `.join(', ')` — amenities, meal items, features, ...)
  /// instead renders full-width beneath its label: squeezing a long
  /// comma-joined list into the narrow space beside a label is what caused
  /// the reported overflow, and it also isn't how the reference design
  /// shows a list value (label on its own line, wrapped text below it).
  Widget _buildDetailRow(_DetailRow row) {
    final bool isList = row.value.contains(',') || row.value.length > 28;

    if (!isList) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(row.label, style: AppTextStyles.caption),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(row.label, style: AppTextStyles.caption),
        const SizedBox(height: 4),
        Text(
          row.value,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// Full displayed address — mirrors the portal's `getFullAddress()`
  /// (PropertyDetails.tsx:566-594): appends metadata's `landmark`/`state`/
  /// `pincode` onto the base location string, deduped, comma-joined.
  /// `addressLine1`/`addressLine2`/`city` are skipped — the Flutter wizard
  /// never collects the first two, and `city` is already folded into
  /// `property.location` (see the `location` getter, `'$locality, $city'`),
  /// so re-appending it would just duplicate the city on every listing.
  /// Previously these three fields saved correctly but had no read site
  /// anywhere on the detail page.
  String _fullAddress(dynamic property) {
    final meta = (property.metadata as Map<String, dynamic>?) ?? const {};
    final String base = (property.location as String?) ?? '';
    final parts = <String>[if (base.isNotEmpty) base];

    final landmark = meta['landmark']?.toString().trim();
    if (landmark != null && landmark.isNotEmpty) {
      // A seller who already typed "Near Hospital" as the landmark itself
      // got "Near Near Hospital" here — this unconditionally prepended
      // "Near " regardless of what the value already said. (The portal has
      // this exact same gap; fixed here anyway since it's a presentation
      // detail, not a business-logic/validation difference.)
      parts.add(
        landmark.toLowerCase().startsWith('near ')
            ? landmark
            : 'Near $landmark',
      );
    }

    final state = meta['state']?.toString().trim();
    if (state != null && state.isNotEmpty) parts.add(state);

    final pincode = meta['pincode']?.toString().trim();
    if (pincode != null && pincode.isNotEmpty) parts.add(pincode);

    final seen = <String>{};
    final unique = parts.where((p) => seen.add(p.toLowerCase())).toList();
    return unique.isEmpty ? base : unique.join(', ');
  }

  // ===========================================================================
  // PROPERTY LOCATION (map card)
  // ===========================================================================

  Widget _buildLocationSection(BuildContext context, dynamic property) {
    final double? rawLatitude = property.latitude as double?;
    final double? rawLongitude = property.longitude as double?;

    // Same treatment as the null case: a corrupted/out-of-range/`(0, 0)`
    // pair is not a real location either, and showing a map centered on
    // one (or a "Get Directions" link built from one) would be actively
    // misleading rather than merely unhelpful. Listings already saved with
    // a mismatched address/coordinates from before this fix existed can't
    // be repaired here — they need to be re-edited, re-pinned and saved
    // again (or fixed directly by the backend team).
    if (!isValidCoordinatePair(rawLatitude, rawLongitude)) {
      return const SizedBox.shrink();
    }
    // Dart can't carry the non-null guarantee `isValidCoordinatePair` just
    // proved through a function-call check the way a plain `== null` check
    // promotes — these two are what the rest of this method actually uses.
    final double latitude = rawLatitude!;
    final double longitude = rawLongitude!;

    final String builderName = property.builderName as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Property Location', style: AppTextStyles.heading3),
            ],
          ),
          const SizedBox(height: 4),
          if (builderName.isNotEmpty)
            Text(
              builderName,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          Text(_fullAddress(property), style: AppTextStyles.caption),
          const SizedBox(height: 12),
          PropertyMapWidget(
            latitude: latitude,
            longitude: longitude,
            title: property.title as String,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _openInGoogleMaps(context, latitude, longitude),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Open in Google Maps',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _getDirections(context, latitude, longitude),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Get Directions',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openInGoogleMaps(
    BuildContext context,
    double latitude,
    double longitude,
  ) async {
    // Defensive: `_buildLocationSection` already hides this button for an
    // invalid pair, but validating again right before actually launching
    // means nothing can ever open a default/incorrect location from here,
    // regardless of how this method got called.
    if (!isValidCoordinatePair(latitude, longitude)) {
      _showInvalidLocationMessage(context);
      return;
    }
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    await _launchMapsUri(context, uri, 'Could not open Google Maps');
  }

  Future<void> _getDirections(
    BuildContext context,
    double latitude,
    double longitude,
  ) async {
    if (!isValidCoordinatePair(latitude, longitude)) {
      _showInvalidLocationMessage(context);
      return;
    }
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
    );
    await _launchMapsUri(context, uri, 'Could not start directions');
  }

  void _showInvalidLocationMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "This listing's location hasn't been set correctly, so it can't "
          'be opened on the map yet.',
        ),
      ),
    );
  }

  Future<void> _launchMapsUri(
    BuildContext context,
    Uri uri,
    String failureMessage,
  ) async {
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    } catch (e) {
      debugPrint('[PropertyDetail] Maps launch error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }

  // ===========================================================================
  // POSTED BY (owner/broker) SECTION
  // Mirrors PropertyDetails.tsx's "Contact Seller" block: display_name,
  // avatar_url, user_type and phone from `profiles`, fetched alongside the
  // property row by PropertyService.getPropertyDetail. Not rendered when no
  // owner profile resolved (see the `if (_ownerProfile != null)` call site),
  // matching the portal's own conditional rendering.
  // ===========================================================================

  Widget _buildOwnerSection(BuildContext context) {
    final owner = _ownerProfile;
    if (owner == null) return const SizedBox.shrink();

    final String name = (owner.companyName?.isNotEmpty ?? false)
        ? owner.companyName!
        : (owner.displayName?.isNotEmpty ?? false)
        ? owner.displayName!
        : 'Property Owner';
    final String role = (owner.userType?.isNotEmpty ?? false)
        ? owner.userType![0].toUpperCase() + owner.userType!.substring(1)
        : 'Contact for details';
    // Prefers this listing's own contact-phone override over the owner's
    // profile phone — mirrors the portal's `effectivePhone` (PropertyDetails
    // .tsx:2171): `contactDetails?.contact_phone || user_profile?.phone`.
    final String? phone = (_contactPhone != null && _contactPhone!.isNotEmpty)
        ? _contactPhone
        : owner.phone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Posted by', style: AppTextStyles.heading3),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.textHint.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openOwnerProfile(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: (owner.avatarUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImageProvider(owner.avatarUrl!)
                            : null,
                        child: (owner.avatarUrl?.isNotEmpty ?? false)
                            ? null
                            : const Icon(
                                Icons.person,
                                color: AppColors.primary,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppTextStyles.heading3.copyWith(
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(role, style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_property?.userId !=
                  Supabase.instance.client.auth.currentUser?.id)
                IconButton(
                  onPressed: () => _messageOwner(context),
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                    color: AppColors.primary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    shape: const CircleBorder(),
                  ),
                ),
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  onPressed: () => _callOwner(context, phone),
                  icon: const Icon(Icons.phone, color: AppColors.primary),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    shape: const CircleBorder(),
                  ),
                ),
            ],
          ),
        ),
        ..._buildOwnerSocialLinks(owner.socialMedia),
      ],
    );
  }

  /// Real messaging with property context — `start_conversation(...,
  /// p_skip_request_gate: true)` (a shared-property context legitimately
  /// skips the message-request gate, matching the portal's
  /// `!!sharedPropertyId` rule), then shares this property into the thread
  /// before opening it, so it's already there on the first fetch.
  Future<void> _messageOwner(BuildContext context) async {
    final property = _property;
    final ownerId = property?.userId;
    if (property == null || ownerId == null || ownerId.isEmpty) return;

    final owner = _ownerProfile;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final service = MessagingService();

    try {
      final conversationId = await service.startConversation(
        ownerId,
        skipRequestGate: true,
      );
      await service.sendPropertyShare(
        threadId: conversationId,
        senderId: Supabase.instance.client.auth.currentUser!.id,
        propertyId: property.id,
        content: 'Shared property: ${property.title}',
      );

      if (!context.mounted) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            kind: ChatThreadKind.conversation,
            threadId: conversationId,
            title: (owner?.companyName?.isNotEmpty ?? false)
                ? owner!.companyName!
                : (owner?.displayName?.isNotEmpty ?? false)
                ? owner!.displayName!
                : 'Property Owner',
            avatarUrl: owner?.avatarUrl,
            initials:
                ((owner?.displayName?.isNotEmpty ?? false)
                        ? owner!.displayName![0]
                        : 'P')
                    .toUpperCase(),
            participantUserId: ownerId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[PropertyDetail] _messageOwner failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't start the conversation.")),
      );
    }
  }

  /// Mirrors PropertyDetails.tsx's owner-card social icon row (Facebook/
  /// Instagram/LinkedIn/YouTube/WhatsApp/Telegram), each shown only when its
  /// own field is present on the already-fetched `social_media` JSON.
  List<Widget> _buildOwnerSocialLinks(Map<String, dynamic>? socialMedia) {
    if (socialMedia == null || socialMedia.isEmpty) return const [];

    String? str(String key) {
      final v = socialMedia[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final links = <_SocialLink>[
      if (str('facebook') != null || str('facebook_page_link') != null)
        _SocialLink(
          FontAwesomeIcons.facebook,
          const Color(0xFF1877F2),
          str('facebook_page_link') ?? str('facebook')!,
        ),
      if (str('instagram') != null)
        _SocialLink(
          FontAwesomeIcons.instagram,
          const Color(0xFFE4405F),
          str('instagram')!,
        ),
      if (str('linkedin') != null)
        _SocialLink(
          FontAwesomeIcons.linkedin,
          const Color(0xFF0A66C2),
          str('linkedin')!,
        ),
      if (str('youtube') != null)
        _SocialLink(
          FontAwesomeIcons.youtube,
          const Color(0xFFFF0000),
          str('youtube')!,
        ),
      if (str('whatsapp') != null)
        _SocialLink(
          FontAwesomeIcons.whatsapp,
          const Color(0xFF25D366),
          'https://wa.me/${str('whatsapp')!.replaceAll(RegExp(r'[^0-9]'), '')}',
        ),
      if (str('telegram') != null)
        _SocialLink(
          FontAwesomeIcons.telegram,
          const Color(0xFF229ED9),
          str('telegram')!.startsWith('http')
              ? str('telegram')!
              : 'https://t.me/${str('telegram')}',
        ),
    ];

    if (links.isEmpty) return const [];

    return [
      const SizedBox(height: 10),
      Row(
        children: [
          for (final link in links) ...[
            GestureDetector(
              onTap: () => _openExternalLink(link.url),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: link.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: FaIcon(link.icon, size: 16, color: link.color),
                ),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  Future<void> _openExternalLink(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[PropertyDetail] Failed to open social link: $e');
    }
  }

  /// Opens the property's actual owner/broker profile — `_property!.userId`,
  /// the same id `PropertyService.getPropertyDetail` used to fetch
  /// `_ownerProfile`, never the signed-in viewer's id.
  void _openOwnerProfile(BuildContext context) {
    final userId = _property?.userId;
    if (userId == null || userId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': userId},
    );
  }

  Future<void> _callOwner(BuildContext context, String phone) async {
    final Uri uri = Uri.parse('tel:$phone');
    try {
      final bool launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call')),
        );
      }
    } catch (e) {
      debugPrint('[PropertyDetail] Call launch error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call')),
        );
      }
    }
  }

  // ===========================================================================
  // OWNERSHIP DOCUMENTS SECTION (Land only, owner-only)
  // ===========================================================================

  /// `metadata.ownershipDocumentPaths` — Land's "Ownership Document Upload"
  /// (legal_details_step.dart). Shown only to the listing's own owner, same
  /// visibility the portal's `handleViewOwnershipDocuments` relies on (the
  /// `documents` bucket has no public-read policy; `get-property-document-url`
  /// is the only read path, and it re-checks `properties` RLS for the caller
  /// — this UI-side check is just so a non-owner never sees a button that
  /// would fail for them, not the actual security boundary).
  Widget _buildOwnershipDocumentsSection(dynamic property) {
    if (property.category != 'land') return const SizedBox.shrink();

    final Map meta = (property.metadata as Map?) ?? const {};
    final paths = meta['ownershipDocumentPaths'];
    final int count = paths is List ? paths.length : 0;
    if (count == 0) return const SizedBox.shrink();

    final String? ownerUserId = property.userId as String?;
    final String? viewerUserId = Supabase.instance.client.auth.currentUser?.id;
    if (ownerUserId == null || ownerUserId != viewerUserId) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: AppColors.textHint.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.folder_shared_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ownership Documents',
                    style: AppTextStyles.heading3.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count == 1
                        ? '1 document on file — visible only to you'
                        : '$count documents on file — visible only to you',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _isLoadingOwnershipDocs
                  ? null
                  : () => _viewOwnershipDocuments(property.id as String),
              child: _isLoadingOwnershipDocs
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('View'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewOwnershipDocuments(String propertyId) async {
    setState(() => _isLoadingOwnershipDocs = true);
    try {
      final docs = await _propertyService.getOwnershipDocumentUrls(propertyId);
      if (!mounted) return;
      setState(() => _isLoadingOwnershipDocs = false);
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _OwnershipDocumentsSheet(documents: docs),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingOwnershipDocs = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ===========================================================================
  // TAGS / HASHTAGS SECTION
  // ===========================================================================

  /// `property.statusTags` — despite the name, `PropertyModel.fromSupabase`
  /// populates it straight from the `hashtags` column (`json['hashtags']`,
  /// property_model.dart) for every real (non-dummy-data) listing; it's not
  /// touched here to avoid disturbing `statusTags`' existing, differently-
  /// themed use elsewhere (Compare screen, search quick-preview).
  Widget _buildHashtagsSection(dynamic property) {
    final List<String> hashtags = (property.statusTags as List).cast<String>();
    if (hashtags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tags', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in hashtags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    '#$tag',
                    style: AppTextStyles.chip.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // AMENITIES SECTION
  // ===========================================================================

  Widget _buildAmenitiesSection(dynamic property) {
    final List amenities = property.amenities as List;
    // Mirrors the reference's showAllAmenities/PREVIEW_COUNT toggle
    // (PropertyDetails.tsx:2276-2279) — a preview slice by count, since this
    // widget's flat icon row has no per-category grouping to slice by.
    const int previewCount = 6;
    final bool canExpand = amenities.length > previewCount;
    final List visibleAmenities = _showAllAmenities || !canExpand
        ? amenities
        : amenities.sublist(0, previewCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Amenities', style: AppTextStyles.heading3),
            if (canExpand)
              TextButton(
                onPressed: () {
                  setState(() {
                    _showAllAmenities = !_showAllAmenities;
                  });
                },
                child: Text(_showAllAmenities ? 'Show less' : 'View all'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 128,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 0),
            itemCount: visibleAmenities.length,
            itemBuilder: (BuildContext context, int index) {
              final amenity = visibleAmenities[index];
              final Color color = Color(
                int.parse((amenity.color as String).replaceAll('#', '0xFF')),
              );
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Container(
                  width: 96,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.textHint.withOpacity(0.2),
                    ),
                  ),
                  child: AmenityIconTile(
                    icon: _getIconFromString(amenity.icon as String),
                    label: amenity.name as String,
                    color: color,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // NEARBY PLACES SECTION
  // ===========================================================================

  Widget _buildNearbyPlacesSection(dynamic property) {
    // Mirrors the reference's showAllNearby/PREVIEW_COUNT(4) toggle
    // (PropertyDetails.tsx:2194-2195, 2256).
    final bool canExpand = _nearbyPlaces.length > 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Nearby Places', style: AppTextStyles.heading3),
            if (canExpand)
              TextButton(
                onPressed: () {
                  setState(() {
                    _showAllNearby = !_showAllNearby;
                  });
                },
                child: Text(_showAllNearby ? 'Show less' : 'View all'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _buildNearbyPlacesContent(),
      ],
    );
  }

  /// Renders the loading / empty / loaded states for the live Nearby Places
  /// list fetched via NearbyPlacesService.
  Widget _buildNearbyPlacesContent() {
    if (_isLoadingNearbyPlaces) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_nearbyPlaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No nearby places found', style: AppTextStyles.caption),
        ),
      );
    }

    final List<NearbyPlace> visiblePlaces =
        _showAllNearby || _nearbyPlaces.length <= 4
        ? _nearbyPlaces
        : _nearbyPlaces.sublist(0, 4);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: visiblePlaces.length,
      itemBuilder: (BuildContext context, int index) {
        final NearbyPlace place = visiblePlaces[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.textHint.withOpacity(0.2)),
          ),
          child: NearbyPlaceRow(
            name: place.name,
            type: NearbyPlacesService.labelForType(place.type),
            distance: place.distance,
            duration: place.duration,
            icon: NearbyPlacesService.iconForType(place.type),
            color: NearbyPlacesService.colorForType(place.type),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // RELATED PROPERTIES SECTION
  // ===========================================================================

  Widget _buildRelatedPropertiesSection(BuildContext context) {
    final compareProvider = context.watch<CompareProvider>();
    if (_isLoadingRelated) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_relatedProperties.isEmpty) {
      return const SizedBox.shrink();
    }

    // Same card as the Feed shows (image, poster, tags, price, location and
    // the like / save / comment / share row).
    if (_relatedFeedItems.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Related Properties', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          for (final item in _relatedFeedItems) FeedItemCard(item: item),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Related Properties', style: AppTextStyles.heading3),
        const SizedBox(height: 12),
        SizedBox(
          height: 320,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _relatedProperties.length,
            itemBuilder: (context, index) {
              final related = _relatedProperties[index];
              return PropertyCardHorizontal(
                property: related,
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppConstants.propertyDetailScreen,
                    arguments: {'propertyId': related.id},
                  );
                },
                onFavoriteToggle: () {
                  Provider.of<PropertyProvider>(
                    context,
                    listen: false,
                  ).toggleShortlist(related.id);
                },
                isInCompare: compareProvider.isSelected(related.id),
                onCompareToggle: () => handleCompareToggle(context, related),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BOTTOM ACTION BAR — unchanged
  // ===========================================================================

  Widget _buildBottomBar(
    BuildContext context,
    dynamic property,
    PropertyProvider propertyProvider,
  ) {
    // Same pattern already used by the app's other persistent bottom bars
    // (e.g. ProfileStickyActionBar, EditProfile's _SaveBar): grow the total
    // height and bottom padding by the device's real bottom safe-area inset,
    // so the 72 dp button row itself is unchanged but no longer sits flush
    // against — and behind — the Android system nav/gesture area.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 72 + bottomInset,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.textHint, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  _showScheduleBottomSheet(context, property, propertyProvider),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, size: 18),
                  SizedBox(width: 8),
                  Text('Schedule Visit'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SCHEDULE VISIT BOTTOM SHEET — real `property_visit_bookings` insert,
  // matching BookVisitModal.tsx's fields/validation (name/phone regex, date
  // not in the past, time slot list) and never reporting success before
  // Supabase confirms the write.
  // ===========================================================================

  void _showScheduleBottomSheet(
    BuildContext context,
    dynamic property,
    PropertyProvider propertyProvider,
  ) {
    final AuthProvider authProvider = Provider.of<AuthProvider>(
      context,
      listen: false,
    );
    final User? currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to book a visit.')),
      );
      return;
    }

    // Same 9-slot, 10 AM-6 PM visiting-hours day as `BookVisitModal.tsx:71-
    // 81`, but suffixed with AM/PM here — the portal's own bare "01:00" etc.
    // is ambiguous (is that 1 AM or 1 PM?), which is exactly the "no AM/PM"
    // problem being fixed. `VisitFormValidation.isSlotDisabled` only reads
    // the digits before the first ':', so the added suffix doesn't change
    // its behaviour.
    const List<String> timeSlots = [
      '10:00 AM',
      '11:00 AM',
      '12:00 PM',
      '01:00 PM',
      '02:00 PM',
      '03:00 PM',
      '04:00 PM',
      '05:00 PM',
      '06:00 PM',
    ];

    final TextEditingController nameController = TextEditingController(
      text: authProvider.userName.isNotEmpty
          ? authProvider.userName
          : (currentUser.userMetadata?['full_name']?.toString() ?? ''),
    );
    final TextEditingController phoneController = TextEditingController(
      text:
          currentUser.phone ??
          authProvider.profileRow?['phone']?.toString() ??
          '',
    );
    // `BookVisitModal.tsx`'s optional Message textarea — was missing here
    // entirely even though `VisitBookingService.createBooking` already
    // accepted it.
    final TextEditingController messageController = TextEditingController();

    DateTime? selectedDate;
    String? selectedTime;
    // Non-null only when [selectedTime] came from the custom time picker
    // (as opposed to one of the fixed [timeSlots] chips) — lets the "Custom"
    // chip show/highlight the picked time and lets a fixed-slot tap clear it.
    TimeOfDay? customTime;
    String? nameError;
    String? phoneError;
    String? dateError;
    String? timeError;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setModalState) {
            bool isSlotDisabled(String time) {
              final DateTime? date = selectedDate;
              if (date == null) return false;
              return VisitFormValidation.isSlotDisabled(
                time,
                date,
                DateTime.now(),
              );
            }

            // "11:30 AM" / "4:45 PM" — matches the format the user picks in
            // the native time picker, distinct from the fixed slots' bare
            // "HH:00" labels so a saved custom time is unambiguous.
            String formatCustomTime(TimeOfDay time) {
              final int hour12 = time.hourOfPeriod == 0
                  ? 12
                  : time.hourOfPeriod;
              final String minute = time.minute.toString().padLeft(2, '0');
              final String period = time.period == DayPeriod.am ? 'AM' : 'PM';
              return '$hour12:$minute $period';
            }

            // `VisitFormValidation.isSlotDisabled` only understands the fixed
            // slots' bare "HH:00" labels (its afternoon heuristic would
            // misread an AM/PM custom string), so a custom pick gets its own
            // straightforward past-time check instead of being run through it.
            bool isCustomTimePast(DateTime date, TimeOfDay time) {
              final DateTime now = DateTime.now();
              final bool isToday =
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              if (!isToday) return false;
              return (time.hour * 60 + time.minute) <=
                  (now.hour * 60 + now.minute);
            }

            Future<void> pickCustomTime() async {
              final TimeOfDay? picked = await showTimePicker(
                context: ctx,
                initialTime: customTime ?? TimeOfDay.now(),
                // Force the 12-hour AM/PM dial regardless of the device's
                // own 24-hour-clock setting, per the required hour/minute/
                // AM-PM format.
                builder: (BuildContext pickerContext, Widget? child) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      pickerContext,
                    ).copyWith(alwaysUse24HourFormat: false),
                    child: child!,
                  );
                },
              );
              if (picked == null) return;
              setModalState(() {
                customTime = picked;
                selectedTime = formatCustomTime(picked);
                timeError = null;
              });
            }

            Future<void> pickDate() async {
              final DateTime now = DateTime.now();
              final DateTime today = DateTime(now.year, now.month, now.day);
              final DateTime? picked = await showDatePicker(
                context: ctx,
                initialDate: selectedDate ?? today,
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
              );
              if (picked != null) {
                setModalState(() {
                  selectedDate = picked;
                  dateError = null;
                  if (customTime != null) {
                    if (isCustomTimePast(picked, customTime!)) {
                      selectedTime = null;
                      customTime = null;
                    }
                  } else if (selectedTime != null &&
                      isSlotDisabled(selectedTime!)) {
                    selectedTime = null;
                  }
                });
              }
            }

            Future<void> submit() async {
              if (isSubmitting) return; // guards against a double tap
              final String name = nameController.text.trim();
              final String phone = phoneController.text.trim();
              setModalState(() {
                nameError = VisitFormValidation.nameError(name);
                phoneError = VisitFormValidation.phoneError(phone);
                dateError = selectedDate == null ? 'Please select date' : null;
                if (selectedTime == null) {
                  timeError = 'Please select time';
                } else if (customTime != null &&
                    selectedDate != null &&
                    isCustomTimePast(selectedDate!, customTime!)) {
                  timeError = 'Please pick a time later than now';
                } else {
                  timeError = null;
                }
              });
              if (nameError != null ||
                  phoneError != null ||
                  dateError != null ||
                  timeError != null) {
                return;
              }

              setModalState(() => isSubmitting = true);
              try {
                await _visitBookingService.createBooking(
                  propertyId: property.id as String,
                  visitorName: name,
                  visitorPhone: phone,
                  preferredDate: selectedDate!,
                  preferredTime: selectedTime!,
                  message: messageController.text,
                  ownerName: _ownerProfile?.displayName,
                  ownerPhone: _ownerProfile?.phone,
                );
                if (!mounted) return;
                Navigator.pop(sheetContext);
                _showSuccessDialog(context, selectedDate!, selectedTime!);
              } catch (e) {
                if (!mounted) return;
                setModalState(() => isSubmitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_describeBookingError(e))),
                );
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textHint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Schedule a Visit', style: AppTextStyles.heading2),
                    const SizedBox(height: 4),
                    Text(
                      property.title as String,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        errorText: nameError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: 'Phone *',
                        errorText: phoneError,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Select Date',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        selectedDate == null
                            ? 'Pick a date'
                            : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                      ),
                    ),
                    if (dateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          dateError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Select Time Slot',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...timeSlots.map((String time) {
                          final bool isSelected =
                              customTime == null && time == selectedTime;
                          final bool disabled = isSlotDisabled(time);
                          return ChoiceChip(
                            label: Text(time),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: disabled
                                ? AppColors.textHint.withOpacity(0.15)
                                : AppColors.cardBackground,
                            // The app's global ChipThemeData sets `side:
                            // BorderSide.none`, and this chip's background
                            // matches the sheet's own — with no outline an
                            // unselected slot rendered as plain floating
                            // text instead of a chip. A visible outline here
                            // (only, not app-wide) fixes that.
                            side: isSelected
                                ? BorderSide.none
                                : BorderSide(
                                    color: AppColors.textHint.withOpacity(0.4),
                                  ),
                            labelStyle: AppTextStyles.chip.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : (disabled
                                        ? AppColors.textHint
                                        : AppColors.textSecondary),
                            ),
                            onSelected: disabled
                                ? null
                                : (bool selected) {
                                    if (selected) {
                                      setModalState(() {
                                        selectedTime = time;
                                        customTime = null;
                                        timeError = null;
                                      });
                                    }
                                  },
                          );
                        }),
                        // Lets the user pick any hour/minute/AM-PM combination
                        // via the native 12-hour time picker, in addition to
                        // (not instead of) the fixed slots above.
                        ChoiceChip(
                          avatar: Icon(
                            Icons.access_time,
                            size: 16,
                            color: customTime != null
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          label: Text(
                            customTime != null ? selectedTime! : 'Custom',
                          ),
                          selected: customTime != null,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.cardBackground,
                          side: customTime != null
                              ? BorderSide.none
                              : BorderSide(
                                  color: AppColors.textHint.withOpacity(0.4),
                                ),
                          labelStyle: AppTextStyles.chip.copyWith(
                            color: customTime != null
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          onSelected: (_) => pickCustomTime(),
                        ),
                      ],
                    ),
                    if (timeError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          timeError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Message',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Any requirements...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Confirm Schedule',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSuccessDialog(BuildContext context, DateTime date, String time) {
    final String formattedDate = '${date.day}/${date.month}/${date.year}';
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Scheduled!'),
          ],
        ),
        content: Text(
          'Your visit is successfully scheduled for $formattedDate at $time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              try {
                if (Navigator.canPop(context)) {
                  Navigator.pushNamed(context, '/visits');
                }
              } catch (e) {
                debugPrint('[PropertyDetail] Navigate to visits error: $e');
              }
            },
            child: const Text('View Visits'),
          ),
        ],
      ),
    );
  }

  String _describeBookingError(Object error) =>
      describeSubmitError(error, "Couldn't book this visit");

  // ===========================================================================
  // ICON HELPER
  // ===========================================================================

  IconData _getIconFromString(String iconString) {
    final String key = iconString.startsWith('Icons.')
        ? iconString.substring('Icons.'.length)
        : iconString;

    switch (key) {
      case 'apartment':
        return Icons.apartment;
      case 'pool':
        return Icons.pool;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'child_care':
        return Icons.child_care;
      case 'security':
        return Icons.security;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'school':
        return Icons.school;
      case 'train':
        return Icons.train;
      case 'business':
        return Icons.business;
      case 'hotel':
        return Icons.hotel;
      case 'movie':
        return Icons.movie;
      case 'directions_car':
        return Icons.directions_car;
      case 'home':
        return Icons.home;
      case 'directions_run':
        return Icons.directions_run;
      case 'sports_soccer':
        return Icons.sports_soccer;
      case 'groups':
        return Icons.groups;
      case 'bolt':
        return Icons.bolt;
      case 'elevator':
        return Icons.elevator;
      case 'local_parking':
        return Icons.local_parking;
      case 'check_circle':
        return Icons.check_circle;
      default:
        debugPrint('[PropertyDetail] Unknown icon string: $iconString');
        return Icons.circle;
    }
  }
}

// =============================================================================
// Small private value holders for the Property Information grid and
// Highlights row — kept file-local since they're only used here.
// =============================================================================

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem(this.icon, this.label, this.value);
}

class _SocialLink {
  final FaIconData icon;
  final Color color;
  final String url;

  const _SocialLink(this.icon, this.color, this.url);
}

class _DetailRow {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);
}

class _DetailGroup {
  final String title;
  final List<_DetailRow> rows;
  final List<_InfoItem> tiles;

  const _DetailGroup(this.title, this.rows, [this.tiles = const []]);
}

// The listing form's own step headings (post_property_screen.dart's
// `stepHeadings`), in the order the seller fills them in. The property page
// groups its information under these same titles.
const String _kStepBasic = 'Basic Information';
const String _kStepDimensions = 'Dimensions & Layout';
const String _kStepCondition = 'Condition & Furnishing';
const String _kStepAmenities = 'Amenities & Facilities';
const String _kStepLegal = 'Legal & Approvals';
const String _kStepPricing = 'Pricing & Terms';
const String _kStepContact = 'Contact Details';

const List<String> _kListingStepTitles = [
  _kStepBasic,
  _kStepDimensions,
  _kStepCondition,
  _kStepAmenities,
  _kStepLegal,
  _kStepPricing,
  _kStepContact,
];

/// `plotAreaUnit` ids the shared `kAreaUnitLabels` map doesn't cover —
/// property_dimensions_step.dart's commercial Plot Area field uses its own
/// local unit list (`kPlotAreaUnits`) rather than the generic area-unit
/// list, and `sq_yd` specifically has no equivalent in `kAreaUnitLabels`
/// (which keys on `sq_yards` instead).
const Map<String, String> _kPlotAreaUnitLabelFallback = {
  'sq_yd': 'Square Yards',
};

/// Which step each of the older detail groups belonged to.
const Map<String, String> _kLegacyGroupStep = {
  'Room Details': _kStepDimensions,
  'Additional Features': _kStepAmenities,
  'Condition & Availability': _kStepCondition,
  'Utilities & Infrastructure': _kStepAmenities,
  'Legal & Society': _kStepLegal,
  'Financial & Pricing': _kStepPricing,
  'Construction & Land': _kStepDimensions,
  'Land Specification': _kStepDimensions,
  'PG Amenities': _kStepAmenities,
  'Food & Services': _kStepCondition,
  'PG Specific Details': _kStepAmenities,
  'Tenant Preferences': _kStepAmenities,
  'Contact Preferences': _kStepContact,
};

/// Rows whose own field belongs to a different step than their old group.
const Map<String, String> _kRowLabelStep = {
  'Facing': _kStepDimensions,
  'Land Type': _kStepBasic,
  // Collected on Basic Info (basic_info_step.dart's land Subtype select),
  // same as the sibling 'Land Type' row above — not a Dimensions-step
  // field despite living in the "Land Specification" group alongside
  // front/back/right/left, which genuinely are Dimensions fields.
  'Land Sub-type': _kStepBasic,
  'Project Status': _kStepBasic,
  'Project Name': _kStepBasic,
  'Builder Name': _kStepBasic,
  'PG Property Type': _kStepBasic,
  'Sharing Type': _kStepDimensions,
  'Meal Types': _kStepCondition,
  'Notice Period': _kStepPricing,
  'Lock-in Period': _kStepPricing,
  'Visitor Policy': _kStepLegal,
  'PG Name': _kStepBasic,
  'Building Type': _kStepBasic,
  'Property Status': _kStepBasic,
  'Quiet Hours / Gate Closing Time': _kStepLegal,
  // "Building Facilities" (its own _DetailGroup) defaults to Amenities &
  // Facilities, correct for most of its rows — these two specifically come
  // from the commercial Condition step instead (condition_step.dart's
  // Building Condition card), not Amenities.
  'Building Age': _kStepCondition,
  'Building Ownership Type': _kStepCondition,
};

/// Property comments — reuses `CommentService`/`ReelComment` (already
/// generic: postId + postType, not reel-specific) with `post_type:
/// 'property'`, the same `post_comments` table the reference's
/// CommentsPanel reads for properties. No new comment system.
class _PropertyCommentsSheet extends StatefulWidget {
  const _PropertyCommentsSheet({
    required this.propertyId,
    required this.commentsEnabled,
  });

  final String propertyId;
  final bool commentsEnabled;

  @override
  State<_PropertyCommentsSheet> createState() => _PropertyCommentsSheetState();
}

class _PropertyCommentsSheetState extends State<_PropertyCommentsSheet> {
  static const String _kPostType = 'property';

  final CommentService _service = CommentService();
  final TextEditingController _input = TextEditingController();

  List<ReelComment>? _comments;
  bool _loadFailed = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await _service.fetchComments(
        widget.propertyId,
        _kPostType,
      );
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('[PropertyDetail] fetchComments failed: $e');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _submit() async {
    final content = _input.text.trim();
    if (content.isEmpty || _submitting) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to comment')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final comment = await _service.submitComment(
        postId: widget.propertyId,
        postType: _kPostType,
        userId: userId,
        content: content,
      );
      if (!mounted) return;
      setState(() {
        _comments = [comment, ...?_comments];
        _input.clear();
      });
    } catch (e) {
      debugPrint('[PropertyDetail] submitComment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't post comment")));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Optimistic remove + rollback on failure — mirrors the portal's
  // CommentsPanel `deleteComment`.
  Future<void> _delete(ReelComment comment) async {
    // Ask first - a deleted comment cannot be brought back.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete comment?'),
        content: const Text(
          'This comment will be removed permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previous = _comments;
    setState(() {
      _comments = previous?.where((c) => c.id != comment.id).toList();
    });
    try {
      await _service.deleteComment(comment.id);
      if (mounted) showOverlayToast(context, 'Comment deleted successfully');
    } catch (e) {
      debugPrint('[PropertyDetail] deleteComment failed: $e');
      if (!mounted) return;
      setState(() => _comments = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.6,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('Comments', style: AppTextStyles.heading3),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
            if (widget.commentsEnabled)
              _buildInputBar()
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Comments are turned off for this listing',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            Text('Could not load comments', style: AppTextStyles.body),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final comments = _comments;
    if (comments == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mode_comment_outlined,
              size: 56,
              color: AppColors.textHint.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text('No comments yet', style: AppTextStyles.body),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: comments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildCommentRow(comments[index]),
    );
  }

  /// Opens the commenter's own public profile — `comment.userId`, same
  /// pattern as the property page's own `_openOwnerProfile`.
  void _openCommenterProfile(String userId) {
    if (userId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': userId},
    );
  }

  Widget _buildCommentRow(ReelComment comment) {
    final name = (comment.authorName?.isNotEmpty ?? false)
        ? comment.authorName!
        : 'User';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openCommenterProfile(comment.userId),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: (comment.authorAvatarUrl?.isNotEmpty ?? false)
                ? NetworkImage(comment.authorAvatarUrl!)
                : null,
            child: (comment.authorAvatarUrl?.isNotEmpty ?? false)
                ? null
                : Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openCommenterProfile(comment.userId),
                child: Text(
                  name,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                comment.content,
                style: AppTextStyles.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        // Only the commenter sees the delete option — same rule as the
        // portal (and re-enforced by the `property-comments` function).
        if (comment.userId == Supabase.instance.client.auth.currentUser?.id)
          IconButton(
            onPressed: () => _delete(comment),
            tooltip: 'Delete comment',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  filled: true,
                  fillColor: AppColors.cardBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Highlight {
  final String label;
  final IconData icon;
  final Color color;

  const _Highlight(this.label, this.icon, this.color);
}

/// Lists a Land listing's ownership documents, each opening its signed URL
/// externally (the file may be a PDF or an image — letting the OS/browser
/// pick the viewer is simpler and more reliable than building one in-app).
/// URLs are already short-lived (5 minutes, set by the edge function), so
/// this sheet is meant to be used right after fetching them, not cached.
class _OwnershipDocumentsSheet extends StatelessWidget {
  const _OwnershipDocumentsSheet({required this.documents});

  final List<({String path, String url})> documents;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ownership Documents',
                  style: AppTextStyles.heading3.copyWith(fontSize: 15),
                ),
              ),
            ),
            if (documents.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Couldn't open any of these documents right now.",
                  style: AppTextStyles.caption,
                ),
              )
            else
              for (int i = 0; i < documents.length; i++)
                ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    'Document ${i + 1}',
                    style: AppTextStyles.body.copyWith(fontSize: 14),
                  ),
                  trailing: const Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: AppColors.textHint,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(documents[i].url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A video slide in the hero carousel: the video's first frame (muted, not
/// playing) under a play button. Tapping opens the full-screen player. The
/// PageView builds slides lazily, so a controller only exists while its
/// slide is on or next to the screen.
class _PropertyVideoSlide extends StatefulWidget {
  const _PropertyVideoSlide({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  State<_PropertyVideoSlide> createState() => _PropertyVideoSlideState();
}

class _PropertyVideoSlideState extends State<_PropertyVideoSlide> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          _controller.setVolume(0);
          setState(() => _ready = true);
        })
        .catchError((Object e) {
          debugPrint('[PropertyDetail] Video preview failed: $e');
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_ready)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
