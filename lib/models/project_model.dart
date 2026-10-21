// models/project_model.dart
//
// A complete `builder_projects` row.
//
// WHY THIS IS NOT `BuilderProjectModel`
// -------------------------------------
// `models/builder_project_model.dart` carries 10 of the table's 30 columns and is
// what `builder_recent_projects_widget.dart` reads. It is deliberately left
// untouched (decision D6): widening it would change the shape every existing
// caller sees, and the wizard needs fields that summary model has no business
// holding. This is the full row; that one stays the dashboard rail's summary.
//
// EVERY FIELD'S NULLABILITY MIRRORS THE COLUMN
// --------------------------------------------
// 24 of these columns are NOT NULL after
// `20270315000000_no_null_listing_and_project_columns.sql`, so the matching
// fields here are non-nullable and parse through a typed fallback. The only two
// that are genuinely nullable in the database — `completion_date` and
// `possession_date` — are the only two nullable fields below. That symmetry is
// the point: if a field here is nullable, the column is too.
import 'package:flutter/foundation.dart';

import '../core/constants/project_options.dart';

@immutable
class ProjectModel {
  // ── Identity ─────────────────────────────────────────────────────────────
  final String id;
  final String builderId;

  // ── Basic info (step 0) ──────────────────────────────────────────────────
  final String title;
  final String description;
  final String projectType;
  final String location;

  /// Street address, state, pincode and a nearby landmark — added by
  /// `20270416000000_add_builder_project_location_fields.sql` so this wizard
  /// can capture the same location detail the Property Listing form already
  /// does. All four are nullable `text` columns; a default of '' is used
  /// rather than modelling them nullable, matching how every other plain-text
  /// column here (e.g. [location]) is handled.
  final String addressLine1;
  final String state;
  final String pincode;
  final String landmark;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  /// `active | under_construction | completed | inactive`. Only `active` is
  /// exposed by the public read policy.
  final String status;

  /// `pending` on insert; only an admin can move it.
  final String approvalStatus;

  // ── Details (step 1) ─────────────────────────────────────────────────────
  final int totalUnits;
  final int availableUnits;
  final double priceRangeMin;
  final double priceRangeMax;
  final double areaSqftMin;
  final double areaSqftMax;

  /// `date` columns — the two nullable ones.
  final DateTime? completionDate;
  final DateTime? possessionDate;

  final String reraNumber;

  // ── Contact & media (step 2) ─────────────────────────────────────────────
  final String websiteUrl;
  final String contactNumber;
  final String logoUrl;
  final String brochureUrl;

  /// Duplicates `mapImages.first`. The portal keeps both in sync on every write
  /// (`BuilderProjectWizard.tsx:518`); see PD7 in the implementation plan.
  final String masterLayoutUrl;

  /// Master-plan layouts.
  final List<String> mapImages;

  /// The project's own photographs.
  final List<String> otherImages;

  /// The flattened gallery the rest of the app reads:
  /// `[...mediaUrls, ...otherImages, ...mapImages]` at write time.
  final List<String> mediaUrls;

  final List<String> videosUrls;

  // ── Amenities (step 3) ───────────────────────────────────────────────────
  final List<String> amenities;

  // ── Engagement ───────────────────────────────────────────────────────────
  final int likes;
  final int views;

  // ── Never collected by any wizard ────────────────────────────────────────
  /// Both are NOT NULL with default 0, and neither the portal's wizard nor this
  /// one collects them — so every project row sits at 0°, 0°. Read here so a map
  /// surface could use them if they are ever populated; see PD1.
  final double latitude;
  final double longitude;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProjectModel({
    required this.id,
    required this.builderId,
    required this.title,
    required this.description,
    required this.projectType,
    required this.location,
    this.addressLine1 = '',
    this.state = '',
    this.pincode = '',
    this.landmark = '',
    required this.status,
    required this.approvalStatus,
    required this.totalUnits,
    required this.availableUnits,
    required this.priceRangeMin,
    required this.priceRangeMax,
    required this.areaSqftMin,
    required this.areaSqftMax,
    this.completionDate,
    this.possessionDate,
    required this.reraNumber,
    required this.websiteUrl,
    required this.contactNumber,
    required this.logoUrl,
    required this.brochureUrl,
    required this.masterLayoutUrl,
    required this.mapImages,
    required this.otherImages,
    required this.mediaUrls,
    required this.videosUrls,
    required this.amenities,
    required this.likes,
    required this.views,
    required this.latitude,
    required this.longitude,
    this.createdAt,
    this.updatedAt,
  });

  /// This project with a different `status`, everything else untouched.
  ///
  /// Added for Spec H's inventory status picker. Narrower than a full `copyWith`
  /// on purpose: `status` is the only field any screen changes in isolation, and a
  /// 30-parameter copy nobody calls would be more surface than the one method
  /// anyone needs. Purely a value-level copy — it issues no query and cannot
  /// change what is stored.
  ProjectModel withStatus(String status) => ProjectModel(
    id: id,
    builderId: builderId,
    title: title,
    description: description,
    projectType: projectType,
    location: location,
    addressLine1: addressLine1,
    state: state,
    pincode: pincode,
    landmark: landmark,
    status: status,
    approvalStatus: approvalStatus,
    totalUnits: totalUnits,
    availableUnits: availableUnits,
    priceRangeMin: priceRangeMin,
    priceRangeMax: priceRangeMax,
    areaSqftMin: areaSqftMin,
    areaSqftMax: areaSqftMax,
    completionDate: completionDate,
    possessionDate: possessionDate,
    reraNumber: reraNumber,
    websiteUrl: websiteUrl,
    contactNumber: contactNumber,
    logoUrl: logoUrl,
    brochureUrl: brochureUrl,
    masterLayoutUrl: masterLayoutUrl,
    mapImages: mapImages,
    otherImages: otherImages,
    mediaUrls: mediaUrls,
    videosUrls: videosUrls,
    amenities: amenities,
    likes: likes,
    views: views,
    latitude: latitude,
    longitude: longitude,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// The column list. Requested explicitly rather than `select('*')` so a column
  /// added by a future migration cannot silently change what this parses.
  static const String columns =
      'id, builder_id, title, description, project_type, location, '
      'address_line1, state, pincode, landmark, status, '
      'approval_status, total_units, available_units, price_range_min, '
      'price_range_max, area_sqft_min, area_sqft_max, completion_date, '
      'possession_date, rera_number, website_url, contact_number, logo_url, '
      'brochure_url, master_layout_url, map_images, other_images, media_urls, '
      'videos_urls, amenities, likes, views, latitude, longitude, created_at, '
      'updated_at';

  factory ProjectModel.fromSupabase(Map<String, dynamic> row) {
    return ProjectModel(
      id: _text(row['id']),
      builderId: _text(row['builder_id']),
      title: _text(row['title']),
      description: _text(row['description']),
      projectType: _text(row['project_type']),
      location: _text(row['location']),
      addressLine1: _text(row['address_line1']),
      state: _text(row['state']),
      pincode: _text(row['pincode']),
      landmark: _text(row['landmark']),
      status: _text(row['status'], fallback: 'active'),
      approvalStatus: _text(row['approval_status'], fallback: 'pending'),
      totalUnits: _int(row['total_units']),
      availableUnits: _int(row['available_units']),
      priceRangeMin: _double(row['price_range_min']),
      priceRangeMax: _double(row['price_range_max']),
      areaSqftMin: _double(row['area_sqft_min']),
      areaSqftMax: _double(row['area_sqft_max']),
      completionDate: _date(row['completion_date']),
      possessionDate: _date(row['possession_date']),
      reraNumber: _text(row['rera_number']),
      websiteUrl: _text(row['website_url']),
      contactNumber: _text(row['contact_number']),
      logoUrl: _text(row['logo_url']),
      brochureUrl: _text(row['brochure_url']),
      masterLayoutUrl: _text(row['master_layout_url']),
      mapImages: _list(row['map_images']),
      otherImages: _list(row['other_images']),
      mediaUrls: _list(row['media_urls']),
      videosUrls: _list(row['videos_urls']),
      amenities: _list(row['amenities']),
      likes: _int(row['likes']),
      views: _int(row['views']),
      latitude: _double(row['latitude']),
      longitude: _double(row['longitude']),
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
    );
  }

  // ── Derived ──────────────────────────────────────────────────────────────

  /// The card image: the flattened gallery first, then the project's own photos,
  /// then a master-plan layout, then the logo.
  ///
  /// Falls through rather than picking one source, because `media_urls` is only
  /// populated by a write that went through this app or the portal's wizard — a
  /// row created before that flattening existed has `other_images` but an empty
  /// `media_urls`.
  String? get coverImage {
    for (final source in [mediaUrls, otherImages, mapImages]) {
      if (source.isNotEmpty) return source.first;
    }
    return logoUrl.isNotEmpty ? logoUrl : null;
  }

  /// Every image, deduplicated and in gallery order.
  List<String> get galleryImages {
    final seen = <String>{};
    final result = <String>[];
    for (final url in [...mediaUrls, ...otherImages, ...mapImages]) {
      if (url.isNotEmpty && seen.add(url)) result.add(url);
    }
    return result;
  }

  String get typeLabel => projectTypeLabel(projectType);
  String get statusLabel => projectStatusLabel(status);

  /// True when this project is visible on public surfaces — the public read
  /// policy's condition, verbatim.
  bool get isPubliclyVisible => status == 'active';

  bool get isApproved => approvalStatus == 'approved';
  bool get isPendingApproval => approvalStatus == 'pending';

  /// True when a price range was actually entered. Both columns default to 0, so
  /// "no price" and "free" are indistinguishable — 0 is treated as absent, which
  /// is what a project listing means by it.
  bool get hasPriceRange => priceRangeMin > 0 || priceRangeMax > 0;

  bool get hasAreaRange => areaSqftMin > 0 || areaSqftMax > 0;

  /// Units sold, derived. Clamped at 0 because nothing stops a builder from
  /// setting `available_units` above `total_units` on an older row — the
  /// cross-field rule is client-side only.
  int get soldUnits {
    final sold = totalUnits - availableUnits;
    return sold > 0 ? sold : 0;
  }

  // ── Parsing helpers ──────────────────────────────────────────────────────

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _date(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static List<String> _list(Object? value) {
    if (value is! List) return const [];
    return value
        .where((item) => item != null && item.toString().trim().isNotEmpty)
        .map((item) => item.toString())
        .toList(growable: false);
  }
}
