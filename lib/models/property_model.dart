// models/property_model.dart
import '../core/utils/listing_price_parser.dart';
import 'amenity_model.dart';

class PropertyModel {
  final String id;
  final String title;
  final String locality;
  final String city;
  final double price;
  final String priceDisplay;
  final String pricePerSqft;
  final int beds;
  final int baths;
  final int sqft;
  // `properties.area_unit` — already selected over the wire (see
  // property_service.dart's select list) but previously parsed nowhere, so
  // every category's "Area" display hardcoded the literal suffix "sqft"
  // regardless of what unit the listing actually used (land alone offers 15:
  // acres, hectares, bigha, ... — see listing_area_units.dart).
  final String? areaUnit;
  // The raw, unrounded `properties.area` value — [sqft] is kept as-is
  // (still an `int`, still rounded) so no existing caller/constructor
  // breaks; this is purely additive. Decimal areas (0.25 Acres, 1200.5
  // Square Feet) previously lost precision the moment they were parsed,
  // since [sqft] rounds to the nearest whole number. Use
  // `formatPropertyArea`/`formatPropertyAreaValue`
  // (core/utils/property_area_formatter.dart) wherever area is displayed,
  // rather than reading [sqft] directly.
  final double? areaValue;
  final int parking;
  final bool isVerified;
  final bool isFeatured;
  final bool isShortlisted;
  final int photoCount;
  final List<String> statusTags;
  final List<AmenityModel> amenities;
  final List<NearbyPlaceModel> nearbyPlaces;
  final String description;
  final String imageUrl;
  final List<String> imageUrls;
  final String builderName;
  final String? propertyType;
  final String? possessionStatus;
  final double? rating;
  final int? reviewCount;
  final bool isTrending;
  final String? floorPlanUrl;
  final String? videoUrl;
  final double? latitude;
  final double? longitude;

  // NEW: parsed straight off the `properties` row (already arrives over the
  // wire via select('*') today — this only adds client-side parsing for it).
  final String? category;
  // Sorting-only fields — never used for budget filtering. Budget filtering
  // stays a client-side comparison against the free-text `price` column,
  // mirroring the website exactly (see PropertyProvider.runSearch).
  final double? priceMin;
  final double? priceMax;
  final double? pricePerUnit;
  final String? currency;
  final bool? isNegotiable;
  final DateTime? availableFrom;
  // Raw `properties.available_from` string, additive alongside
  // [availableFrom]. The column can hold the literal word "Immediately"
  // (see PostPropertyProvider's deliberate `DateTime?` + separate
  // `availableImmediately` bool — "a DateTime? cannot tell 'Immediately'
  // apart from 'not answered yet'"), which `DateTime.tryParse` silently
  // returns null for — losing the signal entirely, not just its format.
  // [availableFrom] itself is left as the actual-date-only `DateTime?` it
  // always was, so no existing caller changes meaning; use
  // [availableFromRaw] to tell "Immediately" apart from "never answered".
  final String? availableFromRaw;
  final int? leaseDurationMonths;
  final int? interestCount;
  final int? likes;
  final String? approvalStatus;
  final String? userId;
  final String? residentialSubtype;
  final String? status;
  final int? views;
  final DateTime? createdAt;

  // NEW: the poster's display name/avatar. `searchProperties` already embeds
  // `user_profile:user_id(display_name,user_type,company_name,avatar_url)` on
  // every row it fetches (property_service.dart) — this only adds client-side
  // exposure of a join that already arrives over the wire and was previously
  // discarded. No new query.
  final String? postedByName;
  final String? postedByAvatarUrl;

  // NEW: the raw `properties.metadata` JSON blob, already fetched over the
  // wire via select('*') today — this only adds client-side exposure of it.
  // Carries the long-tail fields the wizard writes (RERA, facing, legal
  // approvals, utilities, pricing overflow, contact preferences, etc.) that
  // have no dedicated typed column/field above.
  final Map<String, dynamic> metadata;

  // NEW: category-specific fields for the Compare screen (Flutter Compare —
  // Portal Parity work). Sourced from the SAME `properties_residential` /
  // `properties_commercial` / `properties_land` joins `fromSupabase` already
  // receives (see the `beds`/`baths`/`parking` extraction above) — this only
  // adds client-side exposure of columns that were already arriving over the
  // wire and being discarded. No new query, no schema change.
  final int? floorNumber;
  final int? totalFloors;
  final String? facingDirection;
  final int? ageOfProperty;
  final int? balconies;
  final bool? furnished;
  final double? builtUpAreaSqft;
  final double? carpetAreaSqft;
  // Commercial-only.
  final double? powerLoadKw;
  final bool? hasCafeteria;
  final int? conferenceRooms;
  // Land-only.
  final bool? boundaryWall;
  final String? waterSource;
  final double? roadWidthFt;
  final String? soilType;
  final double? slopePercentage;

  PropertyModel({
    required this.id,
    required this.title,
    required this.locality,
    required this.city,
    required this.price,
    required this.priceDisplay,
    required this.pricePerSqft,
    required this.beds,
    required this.baths,
    required this.sqft,
    this.areaUnit,
    this.areaValue,
    required this.parking,
    required this.isVerified,
    required this.isFeatured,
    required this.isShortlisted,
    required this.photoCount,
    required this.statusTags,
    required this.amenities,
    required this.nearbyPlaces,
    required this.description,
    required this.imageUrl,
    // NEW: optional, defaults to empty so every existing call site
    // (direct constructions, fromJson payloads without the field, etc.)
    // keeps compiling untouched.
    this.imageUrls = const [],
    required this.builderName,
    this.propertyType,
    this.possessionStatus,
    this.rating,
    this.reviewCount,
    this.isTrending = false,
    this.floorPlanUrl,
    this.videoUrl,
    this.latitude,
    this.longitude,
    this.category,
    this.priceMin,
    this.priceMax,
    this.pricePerUnit,
    this.currency,
    this.isNegotiable,
    this.availableFrom,
    this.availableFromRaw,
    this.leaseDurationMonths,
    this.interestCount,
    this.likes,
    this.approvalStatus,
    this.userId,
    this.residentialSubtype,
    this.status,
    this.views,
    this.createdAt,
    this.postedByName,
    this.postedByAvatarUrl,
    this.metadata = const {},
    this.floorNumber,
    this.totalFloors,
    this.facingDirection,
    this.ageOfProperty,
    this.balconies,
    this.furnished,
    this.builtUpAreaSqft,
    this.carpetAreaSqft,
    this.powerLoadKw,
    this.hasCafeteria,
    this.conferenceRooms,
    this.boundaryWall,
    this.waterSource,
    this.roadWidthFt,
    this.soilType,
    this.slopePercentage,
  });

  /// Parses a `properties.media_urls` (text[]) value into usable URLs.
  ///
  /// Null-safe and empty-string-filtering, because the column is nullable and
  /// older rows carry `''` entries. Exposed as a static so anything else
  /// reading a joined `properties` row parses it the same way this model does
  /// — [ReelModel] uses it for the reel card's cover image, in the same spirit
  /// as [parseAmenities].
  static List<String> parseMediaUrls(dynamic value) => List<String>.from(
    value ?? const [],
  ).where((url) => url.trim().isNotEmpty).toList();

  /// NEW: the list the UI should actually iterate over.
  /// Falls back to the single [imageUrl] when [imageUrls] wasn't
  /// populated (older cached data, hand-built models, tests, etc.),
  /// so nothing downstream has to special-case an empty list itself.
  List<String> get resolvedImageUrls {
    if (imageUrls.isNotEmpty) return imageUrls;
    return imageUrl.isNotEmpty ? [imageUrl] : const [];
  }

  factory PropertyModel.fromJson(Map<String, dynamic> json) {
    final String singleImage = json['imageUrl'] as String? ?? '';
    return PropertyModel(
      id: json['id'] as String,
      title: json['title'] as String,
      locality: json['locality'] as String,
      city: json['city'] as String,
      price: (json['price'] as num).toDouble(),
      priceDisplay: json['priceDisplay'] as String,
      pricePerSqft: json['pricePerSqft'] as String,
      beds: json['beds'] as int,
      baths: json['baths'] as int,
      sqft: json['sqft'] as int,
      areaUnit: json['areaUnit'] as String?,
      areaValue: (json['areaValue'] as num?)?.toDouble(),
      parking: json['parking'] as int,
      isVerified: json['isVerified'] as bool,
      isFeatured: json['isFeatured'] as bool,
      isShortlisted: json['isShortlisted'] as bool,
      photoCount: json['photoCount'] as int,
      statusTags: (json['statusTags'] as List<dynamic>).cast<String>(),
      amenities: (json['amenities'] as List<dynamic>)
          .map((e) => AmenityModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      nearbyPlaces: (json['nearbyPlaces'] as List<dynamic>)
          .map((e) => NearbyPlaceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      description: json['description'] as String,
      imageUrl: singleImage,
      // Accept an explicit 'imageUrls' array if present; otherwise fall
      // back to wrapping the single 'imageUrl' so old JSON blobs still work.
      imageUrls:
          (json['imageUrls'] as List<dynamic>?)?.cast<String>() ??
          (singleImage.isNotEmpty ? [singleImage] : const []),
      builderName: json['builderName'] as String,
      propertyType: json['propertyType'] as String?,
      possessionStatus: json['possessionStatus'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['reviewCount'] as int?,
      isTrending: json['isTrending'] as bool? ?? false,
      floorPlanUrl: json['floorPlanUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      category: json['category'] as String?,
      priceMin: (json['priceMin'] as num?)?.toDouble(),
      priceMax: (json['priceMax'] as num?)?.toDouble(),
      pricePerUnit: (json['pricePerUnit'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      isNegotiable: json['isNegotiable'] as bool?,
      availableFrom: json['availableFrom'] != null
          ? DateTime.tryParse(json['availableFrom'].toString())
          : null,
      availableFromRaw: json['availableFromRaw'] as String?,
      leaseDurationMonths: json['leaseDurationMonths'] as int?,
      interestCount: json['interestCount'] as int?,
      likes: json['likes'] as int?,
      approvalStatus: json['approvalStatus'] as String?,
      userId: json['userId'] as String?,
      residentialSubtype: json['residentialSubtype'] as String?,
    );
  }

  factory PropertyModel.fromSupabase(Map<String, dynamic> json) {
    // Extract residential/commercial/land data if available. searchProperties
    // embeds the same properties_residential join under the alias
    // 'residentialDetails' (property_service.dart), so both keys are checked
    // — otherwise a PropertyModel built from search results always shows
    // beds/baths as 0 even though the row was fetched.
    final residential =
        json['properties_residential'] as Map<String, dynamic>? ??
        json['residentialDetails'] as Map<String, dynamic>?;
    final commercial = json['properties_commercial'] as Map<String, dynamic>?;
    final land = json['properties_land'] as Map<String, dynamic>?;
    final userProfile = json['user_profile'] as Map<String, dynamic>?;

    // Media lives in properties.media_urls (text[]). This is now the
    // single source of truth for both the gallery and the legacy
    // single-image field below.
    final mediaUrls = parseMediaUrls(json['media_urls']);

    // Extract beds, baths, parking from residential or commercial data
    int beds = 0;
    int baths = 0;
    int parking = 0;

    // Category-specific Compare fields — see the field doc comments above.
    int? floorNumber;
    int? totalFloors;
    String? facingDirection;
    int? ageOfProperty;
    int? balconies;
    bool? furnished;
    double? builtUpAreaSqft;
    double? carpetAreaSqft;
    double? powerLoadKw;
    bool? hasCafeteria;
    int? conferenceRooms;
    bool? boundaryWall;
    String? waterSource;
    double? roadWidthFt;
    String? soilType;
    double? slopePercentage;

    // `as int?` throws (not null) when Postgres/PostgREST hands back a
    // numeric/decimal column as a double — e.g. bedrooms stored as
    // `numeric` rather than `int4`. That throw propagates out of
    // fromSupabase and aborts the whole property load (caught upstream as
    // "Property not found"), taking every section — not just this field —
    // down with it. `(x as num?)?.toInt()` coerces either representation
    // safely.
    if (residential != null) {
      beds = (residential['bedrooms'] as num?)?.toInt() ?? 0;
      baths = (residential['bathrooms'] as num?)?.toInt() ?? 0;
      parking = (residential['parking_spaces'] as num?)?.toInt() ?? 0;
      floorNumber = (residential['floor_number'] as num?)?.toInt();
      totalFloors = (residential['total_floors'] as num?)?.toInt();
      facingDirection = residential['facing_direction']?.toString();
      ageOfProperty = (residential['age_of_property'] as num?)?.toInt();
      balconies = (residential['balconies'] as num?)?.toInt();
      furnished = residential['furnished'] as bool?;
      builtUpAreaSqft = (residential['built_up_area_sqft'] as num?)?.toDouble();
      carpetAreaSqft = (residential['carpet_area_sqft'] as num?)?.toDouble();
    } else if (commercial != null) {
      beds = (commercial['washrooms'] as num?)?.toInt() ?? 0;
      baths = (commercial['washrooms'] as num?)?.toInt() ?? 0;
      parking = (commercial['parking_spaces'] as num?)?.toInt() ?? 0;
      floorNumber = (commercial['floor_number'] as num?)?.toInt();
      totalFloors = (commercial['total_floors'] as num?)?.toInt();
      furnished = commercial['furnished'] as bool?;
      builtUpAreaSqft = (commercial['built_up_area_sqft'] as num?)?.toDouble();
      carpetAreaSqft = (commercial['carpet_area_sqft'] as num?)?.toDouble();
      powerLoadKw = (commercial['power_load_kw'] as num?)?.toDouble();
      hasCafeteria = commercial['cafeteria'] as bool?;
      conferenceRooms = (commercial['conference_rooms'] as num?)?.toInt();
    } else if (land != null) {
      // Land listings have no bedroom/bathroom/parking concept — the
      // sqft-only fields below come straight off properties_land.
      boundaryWall = land['boundary_wall'] as bool?;
      waterSource = land['water_source']?.toString();
      roadWidthFt = (land['road_width_ft'] as num?)?.toDouble();
      soilType = land['soil_type']?.toString();
      slopePercentage = (land['slope_percentage'] as num?)?.toDouble();
    }

    // Extract metadata
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};

    final isFeatured = (json['views'] as int? ?? 0) >= 1;
    final isTrending = (json['views'] as int? ?? 0) >= 20;

    // `resolveEffectivePrice` is the single canonical parser for every
    // price-interpreting call site (this field, budget filtering, price
    // sorting) — see listing_price_parser.dart. It safely handles Indian
    // comma grouping, a ₹ prefix, and L/Lakh/Cr suffixes, none of which a
    // bare `double.tryParse` on the raw text understands, and it falls back
    // to `price_min` only when `price` itself is unparseable.
    final effectivePrice = resolveEffectivePrice(json);

    return PropertyModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      locality: json['location'] ?? '',
      city: metadata['city']?.toString() ?? json['city']?.toString() ?? '',
      // Stays a non-nullable double (0 = unknown) rather than widening this
      // field's type, since a genuine parse never yields a non-positive
      // result — `price <= 0` unambiguously means "unknown" everywhere
      // downstream (budget filtering, price sorting).
      price: effectivePrice ?? 0,
      // Unchanged fallback for the unparseable case — only the successfully
      // resolved path is new here, so display for already-working plain
      // numeric prices is untouched.
      priceDisplay: effectivePrice != null
          ? formatIndianPrice(effectivePrice)
          : formatIndianPrice(json['price']),
      pricePerSqft: metadata['pricePerSqFt']?.toString() ?? '',
      beds: beds,
      baths: baths,
      // `area` is stored as text and can hold a decimal (e.g. "1200.5");
      // int.tryParse rejects the decimal point and silently returns null,
      // which showed as "0 sqft" for any such row.
      sqft: double.tryParse(json['area']?.toString() ?? '0')?.round() ?? 0,
      areaUnit: json['area_unit']?.toString(),
      areaValue: double.tryParse(json['area']?.toString() ?? ''),
      parking: parking,
      // NEW: `properties` has no `is_verified` column at all — the key is
      // always absent, so this must not silently default to true.
      isVerified: json['is_verified'] as bool? ?? false,
      isFeatured: isFeatured,
      isShortlisted: false,
      photoCount: mediaUrls.length,
      statusTags: List<String>.from(json['hashtags'] ?? []),
      amenities: parseAmenities(json['amenities']),
      nearbyPlaces: [],
      description: json['description'] ?? '',
      imageUrl: mediaUrls.isNotEmpty ? mediaUrls.first : '',
      // NEW: full gallery, straight off the DB array.
      imageUrls: mediaUrls,
      // NEW: `properties` has no `builder_name` column — do not fall back
      // to `category`, that mislabels every property's category as its
      // builder name.
      builderName: json['builder_name']?.toString() ?? '',
      propertyType: json['property_type']?.toString(),
      possessionStatus:
          metadata['propertyCondition']?.toString() ??
          json['possession_status']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isTrending: isTrending,
      category: json['category']?.toString(),
      priceMin: (json['price_min'] as num?)?.toDouble(),
      priceMax: (json['price_max'] as num?)?.toDouble(),
      pricePerUnit: (json['price_per_unit'] as num?)?.toDouble(),
      currency: json['currency']?.toString(),
      isNegotiable: json['is_negotiable'] as bool?,
      availableFrom: json['available_from'] != null
          ? DateTime.tryParse(json['available_from'].toString())
          : null,
      availableFromRaw: json['available_from']?.toString(),
      leaseDurationMonths: json['lease_duration_months'] as int?,
      interestCount: json['interest_count'] as int?,
      likes: json['likes'] as int?,
      approvalStatus: json['approval_status']?.toString(),
      userId: json['user_id']?.toString(),
      residentialSubtype: json['residential_subtype']?.toString(),
      status: json['status']?.toString(),
      views: json['views'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      // `display_name` first, `company_name` second — same precedence the
      // People search suggestions already use (search_screen.dart's
      // `_peopleSubtitle`/title fallback) for a joined profile with no name set.
      postedByName:
          userProfile?['display_name']?.toString() ??
          userProfile?['company_name']?.toString(),
      postedByAvatarUrl: userProfile?['avatar_url']?.toString(),
      metadata: metadata,
      floorNumber: floorNumber,
      totalFloors: totalFloors,
      facingDirection: facingDirection,
      ageOfProperty: ageOfProperty,
      balconies: balconies,
      furnished: furnished,
      builtUpAreaSqft: builtUpAreaSqft,
      carpetAreaSqft: carpetAreaSqft,
      powerLoadKw: powerLoadKw,
      hasCafeteria: hasCafeteria,
      conferenceRooms: conferenceRooms,
      boundaryWall: boundaryWall,
      waterSource: waterSource,
      roadWidthFt: roadWidthFt,
      soilType: soilType,
      slopePercentage: slopePercentage,
    );
  }

  static String formatIndianPrice(dynamic value) {
    final price = double.tryParse(value.toString()) ?? 0;

    if (price >= 10000000) {
      return '₹${(price / 10000000).toStringAsFixed(1)} Cr';
    }

    if (price >= 100000) {
      return '₹${(price / 100000).toStringAsFixed(1)} L';
    }

    return '₹${price.toInt()}';
  }

  static List<AmenityModel> parseAmenities(dynamic amenities) {
    if (amenities == null) return [];

    final List<String> items = List<String>.from(amenities);

    const Map<String, Map<String, String>> amenityData = {
      "Swimming Pool": {"icon": "pool", "color": "#2196F3"},
      "Gymnasium": {"icon": "fitness_center", "color": "#F44336"},
      "Clubhouse": {"icon": "home", "color": "#9C27B0"},
      "Children Play Area": {"icon": "child_care", "color": "#FF9800"},
      "Jogging Track": {"icon": "directions_run", "color": "#4CAF50"},
      "Sports Complex": {"icon": "sports_soccer", "color": "#009688"},
      "Shopping Complex": {"icon": "shopping_bag", "color": "#795548"},
      "School": {"icon": "school", "color": "#3F51B5"},
      "Community Hall": {"icon": "groups", "color": "#607D8B"},
      "Security": {"icon": "security", "color": "#4CAF50"},
      "24/7 Power Backup": {"icon": "bolt", "color": "#FFC107"},
      "Elevator": {"icon": "elevator", "color": "#9E9E9E"},
      "Parking": {"icon": "local_parking", "color": "#2196F3"},
    };

    return items.map((name) {
      final data = amenityData[name];

      return AmenityModel(
        id: name,
        name: name,
        icon: data?["icon"] ?? "check_circle",
        color: data?["color"] ?? "#3F51B5",
      );
    }).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'locality': locality,
      'city': city,
      'price': price,
      'priceDisplay': priceDisplay,
      'pricePerSqft': pricePerSqft,
      'beds': beds,
      'baths': baths,
      'sqft': sqft,
      'areaUnit': areaUnit,
      'areaValue': areaValue,
      'parking': parking,
      'isVerified': isVerified,
      'isFeatured': isFeatured,
      'isShortlisted': isShortlisted,
      'photoCount': photoCount,
      'statusTags': statusTags,
      'amenities': amenities.map((e) => e.toJson()).toList(),
      'nearbyPlaces': nearbyPlaces.map((e) => e.toJson()).toList(),
      'description': description,
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
      'builderName': builderName,
      'propertyType': propertyType,
      'possessionStatus': possessionStatus,
      'rating': rating,
      'reviewCount': reviewCount,
      'isTrending': isTrending,
      'floorPlanUrl': floorPlanUrl,
      'videoUrl': videoUrl,
      'latitude': latitude,
      'longitude': longitude,
      'category': category,
      'priceMin': priceMin,
      'priceMax': priceMax,
      'pricePerUnit': pricePerUnit,
      'currency': currency,
      'isNegotiable': isNegotiable,
      'availableFrom': availableFrom?.toIso8601String(),
      'availableFromRaw': availableFromRaw,
      'leaseDurationMonths': leaseDurationMonths,
      'interestCount': interestCount,
      'likes': likes,
      'approvalStatus': approvalStatus,
      'userId': userId,
      'residentialSubtype': residentialSubtype,
      'status': status,
      'views': views,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  PropertyModel copyWith({
    String? id,
    String? title,
    String? locality,
    String? city,
    double? price,
    String? priceDisplay,
    String? pricePerSqft,
    int? beds,
    int? baths,
    int? sqft,
    String? areaUnit,
    double? areaValue,
    int? parking,
    bool? isVerified,
    bool? isFeatured,
    bool? isShortlisted,
    int? photoCount,
    List<String>? statusTags,
    List<AmenityModel>? amenities,
    List<NearbyPlaceModel>? nearbyPlaces,
    String? description,
    String? imageUrl,
    List<String>? imageUrls,
    String? builderName,
    String? propertyType,
    String? possessionStatus,
    double? rating,
    int? reviewCount,
    bool? isTrending,
    String? floorPlanUrl,
    String? videoUrl,
    double? latitude,
    double? longitude,
    String? category,
    double? priceMin,
    double? priceMax,
    double? pricePerUnit,
    String? currency,
    bool? isNegotiable,
    DateTime? availableFrom,
    String? availableFromRaw,
    int? leaseDurationMonths,
    int? interestCount,
    int? likes,
    String? approvalStatus,
    String? userId,
    String? residentialSubtype,
    String? status,
    int? views,
    DateTime? createdAt,
    String? postedByName,
    String? postedByAvatarUrl,
    Map<String, dynamic>? metadata,
    int? floorNumber,
    int? totalFloors,
    String? facingDirection,
    int? ageOfProperty,
    int? balconies,
    bool? furnished,
    double? builtUpAreaSqft,
    double? carpetAreaSqft,
    double? powerLoadKw,
    bool? hasCafeteria,
    int? conferenceRooms,
    bool? boundaryWall,
    String? waterSource,
    double? roadWidthFt,
    String? soilType,
    double? slopePercentage,
  }) {
    return PropertyModel(
      id: id ?? this.id,
      title: title ?? this.title,
      locality: locality ?? this.locality,
      city: city ?? this.city,
      price: price ?? this.price,
      priceDisplay: priceDisplay ?? this.priceDisplay,
      pricePerSqft: pricePerSqft ?? this.pricePerSqft,
      beds: beds ?? this.beds,
      baths: baths ?? this.baths,
      sqft: sqft ?? this.sqft,
      areaUnit: areaUnit ?? this.areaUnit,
      areaValue: areaValue ?? this.areaValue,
      parking: parking ?? this.parking,
      isVerified: isVerified ?? this.isVerified,
      isFeatured: isFeatured ?? this.isFeatured,
      isShortlisted: isShortlisted ?? this.isShortlisted,
      photoCount: photoCount ?? this.photoCount,
      statusTags: statusTags ?? this.statusTags,
      amenities: amenities ?? this.amenities,
      nearbyPlaces: nearbyPlaces ?? this.nearbyPlaces,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      builderName: builderName ?? this.builderName,
      propertyType: propertyType ?? this.propertyType,
      possessionStatus: possessionStatus ?? this.possessionStatus,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isTrending: isTrending ?? this.isTrending,
      floorPlanUrl: floorPlanUrl ?? this.floorPlanUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      category: category ?? this.category,
      priceMin: priceMin ?? this.priceMin,
      priceMax: priceMax ?? this.priceMax,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      currency: currency ?? this.currency,
      isNegotiable: isNegotiable ?? this.isNegotiable,
      availableFrom: availableFrom ?? this.availableFrom,
      availableFromRaw: availableFromRaw ?? this.availableFromRaw,
      leaseDurationMonths: leaseDurationMonths ?? this.leaseDurationMonths,
      interestCount: interestCount ?? this.interestCount,
      likes: likes ?? this.likes,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      userId: userId ?? this.userId,
      residentialSubtype: residentialSubtype ?? this.residentialSubtype,
      status: status ?? this.status,
      views: views ?? this.views,
      createdAt: createdAt ?? this.createdAt,
      postedByName: postedByName ?? this.postedByName,
      postedByAvatarUrl: postedByAvatarUrl ?? this.postedByAvatarUrl,
      metadata: metadata ?? this.metadata,
      floorNumber: floorNumber ?? this.floorNumber,
      totalFloors: totalFloors ?? this.totalFloors,
      facingDirection: facingDirection ?? this.facingDirection,
      ageOfProperty: ageOfProperty ?? this.ageOfProperty,
      balconies: balconies ?? this.balconies,
      furnished: furnished ?? this.furnished,
      builtUpAreaSqft: builtUpAreaSqft ?? this.builtUpAreaSqft,
      carpetAreaSqft: carpetAreaSqft ?? this.carpetAreaSqft,
      powerLoadKw: powerLoadKw ?? this.powerLoadKw,
      hasCafeteria: hasCafeteria ?? this.hasCafeteria,
      conferenceRooms: conferenceRooms ?? this.conferenceRooms,
      boundaryWall: boundaryWall ?? this.boundaryWall,
      waterSource: waterSource ?? this.waterSource,
      roadWidthFt: roadWidthFt ?? this.roadWidthFt,
      soilType: soilType ?? this.soilType,
      slopePercentage: slopePercentage ?? this.slopePercentage,
    );
  }

  String get location => '$locality, $city';
}
