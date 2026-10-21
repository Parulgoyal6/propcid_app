// services/project_service.dart
//
// `builder_projects` CRUD for the builder flow.
//
// A COMPANION, NOT A REPLACEMENT
// ------------------------------
// `builder_project_service.dart` keeps its single `getProjects` method and its
// existing caller (`builder_recent_projects_widget.dart`) untouched — decision D6.
// Nothing here changes an existing method, signature or caller.
//
// WHAT THE PORTAL DOES, AND WHERE
// -------------------------------
//   create/update  BuilderProjectWizard.tsx:493-560
//   list           BuilderProjectsManager.tsx:263-285
//   delete         BuilderProjectsManager.tsx:384-418
//
// RLS is `FOR ALL USING (builder_id = auth.uid()) WITH CHECK (same)`
// (`20250905144708:117-119`), so ownership is already enforced by the database.
// The `.eq('builder_id', …)` on update and delete is the portal's own belt-and-
// braces (`:534`) and is reproduced: it turns "someone else's row" into zero rows
// affected rather than relying on a policy evaluation to refuse.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/validation/project_db_safe.dart';
import '../models/project_model.dart';
import 'resubmit_for_approval.dart';

class ProjectService {
  ProjectService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'builder_projects';

  /// Every project owned by [builderId], newest first.
  ///
  /// `BuilderProjectsManager.tsx:270-277`'s order. Rethrows so the caller can
  /// show a retry rather than an empty list that looks like "no projects yet" —
  /// the behaviour `BuilderProjectService.getProjects` gets wrong by returning
  /// `[]` on failure.
  Future<List<ProjectModel>> listMine(String builderId) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(ProjectModel.columns)
          .eq('builder_id', builderId)
          .order('created_at', ascending: false);

      return rows
          .map(
            (row) => ProjectModel.fromSupabase(Map<String, dynamic>.from(row)),
          )
          .where((project) => project.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('ProjectService.listMine failed: $e');
      rethrow;
    }
  }

  /// Newest active, approved projects — the Home "Latest Projects" rail.
  ///
  /// Mirrors the portal's `LatestProjectsSection.tsx` query: same table
  /// (`builder_projects`, NOT `properties`), same two-flag filter
  /// (`status='active'`, `approval_status='approved'`), same `created_at`
  /// descending order. Kept on this service rather than a new one — this is
  /// exactly the table [ProjectService] already owns, just a public read
  /// instead of an owner-scoped one.
  Future<List<ProjectModel>> listLatestActive({int limit = 8}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(ProjectModel.columns)
          .eq('status', 'active')
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(limit);

      return rows
          .map(
            (row) => ProjectModel.fromSupabase(Map<String, dynamic>.from(row)),
          )
          .where((project) => project.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('ProjectService.listLatestActive failed: $e');
      rethrow;
    }
  }

  /// One project by id, or null when it does not exist or is not visible.
  ///
  /// Readable by anyone when `status = 'active'` (the public policy) and by its
  /// owner in any status.
  Future<ProjectModel?> fetchById(String projectId) async {
    try {
      final row = await _supabase
          .from(_table)
          .select(ProjectModel.columns)
          .eq('id', projectId)
          .maybeSingle();

      if (row == null) return null;
      return ProjectModel.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('ProjectService.fetchById($projectId) failed: $e');
      rethrow;
    }
  }

  /// Every project in [projectIds], in no particular order — for rendering a
  /// liked/saved-projects list from a set of ids (My Activity), where there is
  /// no general "all projects" cache to filter locally the way properties and
  /// reels do. Same visibility as [fetchById]: RLS only returns rows the
  /// caller may see.
  Future<List<ProjectModel>> fetchByIds(List<String> projectIds) async {
    if (projectIds.isEmpty) return [];
    try {
      final rows = await _supabase
          .from(_table)
          .select(ProjectModel.columns)
          .inFilter('id', projectIds);

      return rows
          .map(
            (row) => ProjectModel.fromSupabase(Map<String, dynamic>.from(row)),
          )
          .where((project) => project.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('ProjectService.fetchByIds failed: $e');
      rethrow;
    }
  }

  /// Creates a project and returns the stored row.
  ///
  /// `builder_id` is set here and only here — the portal adds it on insert and
  /// never on update (`:546-547`), because a project cannot change owner.
  Future<ProjectModel> create({
    required String builderId,
    required ProjectDraft draft,
  }) async {
    try {
      final row = await _supabase
          .from(_table)
          .insert({'builder_id': builderId, ...draft.toPayload()})
          .select(ProjectModel.columns)
          .single();

      return ProjectModel.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('ProjectService.create failed: $e');
      rethrow;
    }
  }

  /// Updates a project the caller owns.
  Future<void> update({
    required String projectId,
    required String builderId,
    required ProjectDraft draft,
  }) async {
    try {
      // Re-queue for review first (non-admin owners), like the website.
      await resubmitForApproval(_supabase, table: _table, id: projectId);
      await _supabase
          .from(_table)
          .update(draft.toPayload())
          .eq('id', projectId)
          .eq('builder_id', builderId);
    } catch (e) {
      debugPrint('ProjectService.update($projectId) failed: $e');
      rethrow;
    }
  }

  /// Deletes a project.
  ///
  /// `project_inventory`, `builder_project_offers` and `project_visit_bookings`
  /// all reference `builder_projects(id) ON DELETE CASCADE`, so this removes the
  /// project's inventory, offers and visit bookings with it. The caller is
  /// responsible for confirming that with the user first.
  Future<void> delete({
    required String projectId,
    required String builderId,
  }) async {
    try {
      await _supabase
          .from(_table)
          .delete()
          .eq('id', projectId)
          .eq('builder_id', builderId);
    } catch (e) {
      debugPrint('ProjectService.delete($projectId) failed: $e');
      rethrow;
    }
  }

  /// Moves a project between the four `status` values.
  ///
  /// Anything other than `active` removes it from every public surface, because
  /// the public read policy is `USING (status = 'active')`.
  Future<void> setStatus({
    required String projectId,
    required String builderId,
    required String status,
  }) async {
    try {
      await _supabase
          .from(_table)
          .update({'status': dbText(status, fallback: 'active')})
          .eq('id', projectId)
          .eq('builder_id', builderId);
    } catch (e) {
      debugPrint('ProjectService.setStatus($projectId) failed: $e');
      rethrow;
    }
  }

  /// Recomputes `total_units`/`available_units` from [projectId]'s real
  /// `project_inventory` rows and writes them back here — called by
  /// `ManageUnitsScreen` after a unit is added, edited or deleted, so these
  /// two numbers (shown on the Edit Project form, and as the public page's
  /// own fallback before any inventory exists) stay truthful instead of
  /// freezing at whatever was typed in when the project was created.
  ///
  /// Reads `project_inventory` but never writes it — this file stays the
  /// only writer of `builder_projects`, per this file's own header comment.
  /// A no-op when there are no inventory rows yet: an empty project's
  /// manually-declared plan is the only number that exists at that point,
  /// and must not be zeroed out just because nothing has been tracked yet.
  ///
  /// Swallows failure (logged only) — a missed sync must never surface as an
  /// error on whatever unit-level change already saved successfully.
  Future<void> syncTotalsFromInventory({
    required String projectId,
    required String builderId,
  }) async {
    try {
      final rows = await _supabase
          .from('project_inventory')
          .select('status')
          .eq('project_id', projectId);
      final units = List<Map<String, dynamic>>.from(rows);
      if (units.isEmpty) return;

      final available = units
          .where((u) => u['status']?.toString() == 'available')
          .length;
      await _supabase
          .from(_table)
          .update({'total_units': units.length, 'available_units': available})
          .eq('id', projectId)
          .eq('builder_id', builderId);
    } catch (e) {
      debugPrint(
        'ProjectService.syncTotalsFromInventory($projectId) failed: $e',
      );
    }
  }
}

/// Sentinel for [ProjectDraft.copyWith]: "leave this number as it is".
///
/// Distinguishable from an explicit null, which means "clear it".
const Object unchangedNumber = Object();

int? _pickInt(Object? supplied, int? current) =>
    supplied == unchangedNumber ? current : supplied as int?;

double? _pickNum(Object? supplied, double? current) =>
    supplied == unchangedNumber ? current : supplied as double?;

/// The wizard's form values, and the one place the insert payload is built.
///
/// Separate from [ProjectModel] on purpose: a model is a row that exists, a draft
/// is what the user has typed so far. The draft's numbers are nullable (nothing
/// entered yet); the row's are not (the column is NOT NULL).
@immutable
class ProjectDraft {
  const ProjectDraft({
    this.title = '',
    this.description = '',
    this.projectType = '',
    this.location = '',
    this.addressLine1 = '',
    this.state = '',
    this.pincode = '',
    this.landmark = '',
    this.latitude,
    this.longitude,
    this.totalUnits,
    this.availableUnits,
    this.priceRangeMin,
    this.priceRangeMax,
    this.areaSqftMin,
    this.areaSqftMax,
    this.completionDate = '',
    this.possessionDate = '',
    this.reraNumber = '',
    this.websiteUrl = '',
    this.contactNumber = '',
    this.logoUrl = '',
    this.brochureUrl = '',
    this.mapImages = const [],
    this.otherImages = const [],
    this.videosUrls = const [],
    this.amenities = const [],
  });

  final String title;
  final String description;
  final String projectType;
  final String location;

  /// Street address, state, pincode and a nearby landmark — added by
  /// `20270416000000_add_builder_project_location_fields.sql`. Populated by
  /// [ProjectBasicInfoStep]'s map picker / address search, same as
  /// `location` (city) already was.
  final String addressLine1;
  final String state;
  final String pincode;
  final String landmark;

  /// Set together, from the same map pin or address search that fills the
  /// four fields above. Null until a location is resolved, matching
  /// [priceRangeMin]'s "no value entered yet" convention.
  final double? latitude;
  final double? longitude;

  final int? totalUnits;
  final int? availableUnits;
  final double? priceRangeMin;
  final double? priceRangeMax;
  final double? areaSqftMin;
  final double? areaSqftMax;

  /// ISO `yyyy-MM-dd`, or blank.
  final String completionDate;
  final String possessionDate;

  final String reraNumber;
  final String websiteUrl;
  final String contactNumber;
  final String logoUrl;
  final String brochureUrl;

  final List<String> mapImages;
  final List<String> otherImages;
  final List<String> videosUrls;
  final List<String> amenities;

  /// Seeds the draft from an existing row, for edit mode.
  ///
  /// `media_urls` is deliberately **not** read back: it is derived on every write
  /// from the other three lists (see [toPayload]), so carrying it into the draft
  /// and then re-flattening would duplicate every URL on the second save.
  factory ProjectDraft.fromProject(ProjectModel project) {
    String isoDate(DateTime? value) =>
        value == null ? '' : value.toIso8601String().split('T').first;

    return ProjectDraft(
      title: project.title,
      description: project.description,
      projectType: project.projectType,
      location: project.location,
      addressLine1: project.addressLine1,
      state: project.state,
      pincode: project.pincode,
      landmark: project.landmark,
      latitude: project.latitude,
      longitude: project.longitude,
      totalUnits: project.totalUnits,
      availableUnits: project.availableUnits,
      priceRangeMin: project.priceRangeMin,
      priceRangeMax: project.priceRangeMax,
      areaSqftMin: project.areaSqftMin,
      areaSqftMax: project.areaSqftMax,
      completionDate: isoDate(project.completionDate),
      possessionDate: isoDate(project.possessionDate),
      reraNumber: project.reraNumber,
      websiteUrl: project.websiteUrl,
      contactNumber: project.contactNumber,
      logoUrl: project.logoUrl,
      brochureUrl: project.brochureUrl,
      mapImages: project.mapImages,
      otherImages: project.otherImages,
      videosUrls: project.videosUrls,
      amenities: project.amenities,
    );
  }

  /// The exact row written to `builder_projects`.
  ///
  /// `BuilderProjectWizard.tsx:494-525`, coerced through [dbText] / [dbNum] /
  /// [dbInt] / [dbArray] / [dbDate] so **not one of the 24 NOT NULL columns ever
  /// receives a null**. That is not defensive styling — a null there is a `23502`
  /// and the save fails outright.
  ///
  /// Two things are derived rather than entered:
  ///   * `master_layout_url` mirrors `map_images.first` (`:518`);
  ///   * `media_urls` is the flattened gallery (`:520-524`).
  ///
  /// `latitude` / `longitude` default to 0 (via [dbNum]) until the map picker
  /// on the Basic Info step resolves a location — the portal's own
  /// `GoogleLocationPicker` (`BuilderProjectWizard.tsx:877-906`) fills both the
  /// same way, so this is no longer the "never collected" case decision D4/PD1
  /// once described; that note predates `addressLine1`/`state`/`pincode`/
  /// `landmark`/lat-long being added to the wizard.
  ///
  /// `status` and `approval_status` are also omitted: their column defaults are
  /// `'active'` and `'pending'`, which is what the portal's insert relies on, and
  /// sending `approval_status` from a client would let a builder self-approve.
  Map<String, dynamic> toPayload() {
    final maps = dbArray(mapImages);
    final others = dbArray(otherImages);

    return {
      'title': dbText(title),
      'description': dbText(description),
      'project_type': dbText(projectType),
      'location': dbText(location),
      'address_line1': dbText(addressLine1),
      'state': dbText(state),
      'pincode': dbText(pincode),
      'landmark': dbText(landmark),
      'latitude': dbNum(latitude),
      'longitude': dbNum(longitude),
      'total_units': dbInt(totalUnits),
      'available_units': dbInt(availableUnits),
      'price_range_min': dbNum(priceRangeMin),
      'price_range_max': dbNum(priceRangeMax),
      'area_sqft_min': dbNum(areaSqftMin),
      'area_sqft_max': dbNum(areaSqftMax),
      'amenities': dbArray(amenities),
      // The only two nullable columns in the payload.
      'completion_date': dbDate(completionDate),
      'possession_date': dbDate(possessionDate),
      'rera_number': dbText(reraNumber),
      'map_images': maps,
      'videos_urls': dbArray(videosUrls),
      'other_images': others,
      'brochure_url': dbText(brochureUrl),
      'website_url': dbText(websiteUrl),
      'contact_number': dbText(contactNumber),
      'logo_url': dbText(logoUrl),
      'master_layout_url': maps.isNotEmpty ? dbText(maps.first) : '',
      // The flattened gallery. `media_urls` is not a draft field, so the leading
      // spread the portal has (`...dbArray(formData.media_urls)`) is always empty
      // here and is left out rather than carried as a no-op.
      'media_urls': [...others, ...maps],
    };
  }

  /// [latitude], [longitude], [totalUnits], [availableUnits] and the four
  /// range values take the [unchangedNumber] sentinel rather than defaulting
  /// to null.
  ///
  /// `x ?? this.x` cannot tell "not supplied" from "explicitly cleared", so
  /// clearing a number field would be a silent no-op and its required-field rule
  /// would never fire again — the user would be blocked on submit with no visible
  /// cause. [latitude]/[longitude] need exactly this when an address is edited
  /// after a pin was already dropped: the old coordinates must actually go
  /// away, not just get skipped over. Every other field here is
  /// non-nullable, so `??` is safe for them.
  ProjectDraft copyWith({
    String? title,
    String? description,
    String? projectType,
    String? location,
    String? addressLine1,
    String? state,
    String? pincode,
    String? landmark,
    // `unchangedNumber`-sentinelled, like the four range fields below:
    // `latitude ?? this.latitude` could never express "the address changed,
    // forget the old pin" — an explicit `null` would just vanish back into
    // the coordinate it's supposed to be clearing. Pass `null` explicitly
    // to clear; omit the argument to leave it as it is.
    Object? latitude = unchangedNumber,
    Object? longitude = unchangedNumber,
    Object? totalUnits = unchangedNumber,
    Object? availableUnits = unchangedNumber,
    Object? priceRangeMin = unchangedNumber,
    Object? priceRangeMax = unchangedNumber,
    Object? areaSqftMin = unchangedNumber,
    Object? areaSqftMax = unchangedNumber,
    String? completionDate,
    String? possessionDate,
    String? reraNumber,
    String? websiteUrl,
    String? contactNumber,
    String? logoUrl,
    String? brochureUrl,
    List<String>? mapImages,
    List<String>? otherImages,
    List<String>? videosUrls,
    List<String>? amenities,
  }) {
    return ProjectDraft(
      title: title ?? this.title,
      description: description ?? this.description,
      projectType: projectType ?? this.projectType,
      location: location ?? this.location,
      addressLine1: addressLine1 ?? this.addressLine1,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      landmark: landmark ?? this.landmark,
      latitude: _pickNum(latitude, this.latitude),
      longitude: _pickNum(longitude, this.longitude),
      totalUnits: _pickInt(totalUnits, this.totalUnits),
      availableUnits: _pickInt(availableUnits, this.availableUnits),
      priceRangeMin: _pickNum(priceRangeMin, this.priceRangeMin),
      priceRangeMax: _pickNum(priceRangeMax, this.priceRangeMax),
      areaSqftMin: _pickNum(areaSqftMin, this.areaSqftMin),
      areaSqftMax: _pickNum(areaSqftMax, this.areaSqftMax),
      completionDate: completionDate ?? this.completionDate,
      possessionDate: possessionDate ?? this.possessionDate,
      reraNumber: reraNumber ?? this.reraNumber,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      contactNumber: contactNumber ?? this.contactNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      brochureUrl: brochureUrl ?? this.brochureUrl,
      mapImages: mapImages ?? this.mapImages,
      otherImages: otherImages ?? this.otherImages,
      videosUrls: videosUrls ?? this.videosUrls,
      amenities: amenities ?? this.amenities,
    );
  }

  /// The draft as a plain map, for the wizard's saved draft.
  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'project_type': projectType,
    'location': location,
    'address_line1': addressLine1,
    'state': state,
    'pincode': pincode,
    'landmark': landmark,
    'latitude': latitude,
    'longitude': longitude,
    'total_units': totalUnits,
    'available_units': availableUnits,
    'price_range_min': priceRangeMin,
    'price_range_max': priceRangeMax,
    'area_sqft_min': areaSqftMin,
    'area_sqft_max': areaSqftMax,
    'completion_date': completionDate,
    'possession_date': possessionDate,
    'rera_number': reraNumber,
    'website_url': websiteUrl,
    'contact_number': contactNumber,
    'logo_url': logoUrl,
    'brochure_url': brochureUrl,
    'map_images': mapImages,
    'other_images': otherImages,
    'videos_urls': videosUrls,
    'amenities': amenities,
  };

  /// Restores a saved draft. Unknown and malformed keys are ignored rather than
  /// throwing, so a draft written by an older build still opens.
  factory ProjectDraft.fromJson(Map<String, dynamic> json) {
    List<String> list(Object? value) => dbArray(value);
    int? intOrNull(Object? value) => value == null ? null : dbInt(value);
    double? numOrNull(Object? value) => value == null ? null : dbNum(value);

    return ProjectDraft(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      projectType: json['project_type']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      addressLine1: json['address_line1']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      pincode: json['pincode']?.toString() ?? '',
      landmark: json['landmark']?.toString() ?? '',
      latitude: numOrNull(json['latitude']),
      longitude: numOrNull(json['longitude']),
      totalUnits: intOrNull(json['total_units']),
      availableUnits: intOrNull(json['available_units']),
      priceRangeMin: numOrNull(json['price_range_min']),
      priceRangeMax: numOrNull(json['price_range_max']),
      areaSqftMin: numOrNull(json['area_sqft_min']),
      areaSqftMax: numOrNull(json['area_sqft_max']),
      completionDate: json['completion_date']?.toString() ?? '',
      possessionDate: json['possession_date']?.toString() ?? '',
      reraNumber: json['rera_number']?.toString() ?? '',
      websiteUrl: json['website_url']?.toString() ?? '',
      contactNumber: json['contact_number']?.toString() ?? '',
      logoUrl: json['logo_url']?.toString() ?? '',
      brochureUrl: json['brochure_url']?.toString() ?? '',
      mapImages: list(json['map_images']),
      otherImages: list(json['other_images']),
      videosUrls: list(json['videos_urls']),
      amenities: list(json['amenities']),
    );
  }

  /// True when nothing has been entered — used to decide whether a saved draft is
  /// worth offering to restore.
  bool get isEmpty =>
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      projectType.isEmpty &&
      location.trim().isEmpty &&
      addressLine1.trim().isEmpty &&
      state.trim().isEmpty &&
      pincode.trim().isEmpty &&
      landmark.trim().isEmpty &&
      latitude == null &&
      longitude == null &&
      totalUnits == null &&
      availableUnits == null &&
      priceRangeMin == null &&
      priceRangeMax == null &&
      areaSqftMin == null &&
      areaSqftMax == null &&
      completionDate.isEmpty &&
      possessionDate.isEmpty &&
      reraNumber.trim().isEmpty &&
      websiteUrl.trim().isEmpty &&
      contactNumber.trim().isEmpty &&
      logoUrl.isEmpty &&
      brochureUrl.isEmpty &&
      mapImages.isEmpty &&
      otherImages.isEmpty &&
      videosUrls.isEmpty &&
      amenities.isEmpty;
}
