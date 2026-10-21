import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/utils/public_media_url.dart';
import '../models/available_location.dart';
import '../models/global_search_suggestion.dart';
import '../models/property_detail_bundle.dart';
import '../models/property_model.dart';
import '../models/search_query_params.dart';
import '../models/tagged_project.dart';
import '../providers/post_property_provider.dart';
import '../screens/post_property/listing_constants.dart' show kHouseSubtypes;
import '../screens/post_property/listing_field_keys.dart';
import 'resubmit_for_approval.dart';
import '../screens/post_property/listing_value_aliases.dart';

/// Raw data bundle returned by [PropertyService.fetchForEdit]. Contains the
/// unprocessed Supabase rows so the provider can restore every form field.
class PropertyEditBundle {
  final Map<String, dynamic> propertyRow;
  final Map<String, dynamic>? subtableRow;
  final Map<String, dynamic>? contactRow;

  const PropertyEditBundle({
    required this.propertyRow,
    this.subtableRow,
    this.contactRow,
  });
}

/// Result of [PropertyService.createProperty]. A non-null [propertyId] only
/// means the row was inserted — it does NOT mean the listing is approved or
/// visible to buyers. Callers must check [approvalStatus] (mirrors the same
/// `approval_status` column every buyer-facing query in this file filters
/// on) rather than inferring "live" from the id alone.
class PropertyCreationResult {
  final String propertyId;
  final String? approvalStatus;

  const PropertyCreationResult({
    required this.propertyId,
    required this.approvalStatus,
  });

  bool get isApproved => approvalStatus == 'approved';
}

/// Free-text search stopwords — exact port of Search.tsx's list. Words
/// shorter than 2 characters are dropped regardless of this set.
const Set<String> _searchStopwords = {
  'in',
  'at',
  'for',
  'the',
  'properties',
  'property',
  'show',
  'list',
  'find',
  'search',
  'a',
  'an',
  'of',
  'with',
};

/// The 5 columns Search.tsx OR-ILIKE-matches every remaining search word
/// against.
const List<String> _searchColumns = [
  'title',
  'search_text',
  'location',
  'area',
  'upid',
];

/// `metadata.pgHouseRules` sub-key -> the `PropertyFormData` flag React reads
/// it from (PropertyWizard.tsx:1649). The names differ on both sides of the
/// colon, so this mapping is not derivable.
const Map<String, String> _kPgHouseRuleSources = {
  'visitorEntry': 'pgVisitorEntry',
  'nonVegFood': 'pgNonVegFood',
  'oppositeGender': 'pgOppositeGender',
  'smoking': 'pgSmoking',
  'drinking': 'pgDrinking',
  'loudMusic': 'pgLoudMusic',
  'party': 'pgParty',
};

class PropertyService {
  final _supabase = Supabase.instance.client;

  /// Home feed (hero banner + rails). Matches `searchProperties`' pair of
  /// filters (below) — `status='active'` alone let pending, unapproved
  /// listings appear on the public Home screen.
  Future<List<Map<String, dynamic>>> getProperties() async {
    final data = await _supabase
        .from('properties')
        .select(
          '*,properties_residential(*),properties_commercial(*),properties_land(*)',
        )
        .eq('status', 'active')
        .eq('approval_status', 'approved')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  /// Fetches specific properties by id for the Compare screen — same
  /// active/approved filter and sub-table joins as [getProperties], via the
  /// same safe `inFilter` PostgREST helper every other multi-id lookup in
  /// this codebase uses (e.g. `reels_service.dart`, `messaging_service.dart`)
  /// rather than a raw interpolated `NOT IN (...)` string.
  ///
  /// Used when a persisted/deep-linked compare selection contains an id that
  /// is not already sitting in [PropertyProvider]'s in-memory cache. A
  /// deleted, deactivated or unapproved property simply does not come back —
  /// callers must treat a missing id as "drop this slot", never substitute a
  /// different property.
  Future<List<Map<String, dynamic>>> getPropertiesByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    final data = await _supabase
        .from('properties')
        .select(
          '*,properties_residential(*),properties_commercial(*),properties_land(*)',
        )
        .inFilter('id', ids)
        .eq('status', 'active')
        .eq('approval_status', 'approved');

    return List<Map<String, dynamic>>.from(data);
  }

  /// Mirrors the React SellerWall query (SellerWall.tsx:221–226):
  ///   SELECT * FROM properties WHERE user_id = uid ORDER BY created_at DESC
  /// No status filter — all of the user's listings are returned regardless of
  /// status so the dashboard can show active/inactive/sold badges. Joins the
  /// sub-tables (matching `getProperties()`) because this method also feeds
  /// `ProfileProvider` → `MyContentSection`'s `PropertyCardCompact`, which
  /// does render beds/baths/parking — omitting them silently defaulted those
  /// to 0 there even though the dashboard-only card callers don't need them.
  Future<List<PropertyModel>> getPropertiesByUser(String userId) async {
    final rows = await _supabase
        .from('properties')
        .select(
          '*,properties_residential(*),properties_commercial(*),properties_land(*)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(
      rows,
    ).map((r) => PropertyModel.fromSupabase(r)).toList();
  }

  /// Ports Search.tsx's buildSupabaseQuery/performSearch exactly — same
  /// table, same conditional embedded-selects, same filters, same sort
  /// options. Budget is deliberately NEVER sent as a DB filter here (see
  /// the plan's Risk B): price_min/price_max are sparsely populated, so the
  /// website compares budget against the parsed free-text `price` column
  /// client-side instead — PropertyProvider does that step, not this method.
  ///
  /// [includeRange] controls whether `.range()` pagination is applied
  /// (normal list-mode paging) or a single safety-capped `.limit()` fetch is
  /// used instead (near-me / map modes, which need the whole matching set
  /// at once — see the plan's "Deliberate deviations").
  Future<PropertySearchPage> searchProperties({
    required SearchQueryParams params,
    required int offset,
    required int limit,
    bool includeRange = true,
  }) async {
    final bool postedByActive = params.postedBy != null;
    final bool bhkActive = params.bhk != null;

    final selectFields = <String>[
      '*',
      postedByActive
          ? 'user_profile:user_id!inner(display_name,user_type,company_name,avatar_url)'
          : 'user_profile:user_id(display_name,user_type,company_name,avatar_url)',
      bhkActive
          ? 'residentialDetails:properties_residential!properties_residential_property_id_fkey!inner(bedrooms,bathrooms,parking_spaces,furnished,floor_number,total_floors)'
          : 'residentialDetails:properties_residential!properties_residential_property_id_fkey(bedrooms,bathrooms,parking_spaces,furnished,floor_number,total_floors)',
    ];

    PostgrestFilterBuilder<PostgrestList> query = _supabase
        .from('properties')
        .select(selectFields.join(','))
        .inFilter('status', ['active', 'sold'])
        .eq('approval_status', 'approved');

    if (params.cities.length == 1) {
      query = query.ilike('location', '%${params.cities.first}%');
    } else if (params.cities.length > 1) {
      query = query.or(
        params.cities.map((c) => 'location.ilike.%$c%').join(','),
      );
    }

    if (params.category != null) {
      query = query.eq('category', params.category!);
    }
    if (params.listingType != null) {
      query = query.eq('property_type', params.listingType!);
    }
    if (params.hashtag != null && params.hashtag!.isNotEmpty) {
      query = query.contains('hashtags', [params.hashtag!]);
    }

    final searchText = params.searchText.trim();
    if (searchText.isNotEmpty) {
      final sanitized = searchText.replaceAll(RegExp(r'[,()\\]'), '');
      final words = sanitized
          .split(RegExp(r'\s+'))
          .where(
            (w) => w.length >= 2 && !_searchStopwords.contains(w.toLowerCase()),
          );
      final clauses = <String>[
        for (final word in words)
          for (final col in _searchColumns) '$col.ilike.%$word%',
      ];
      if (clauses.isNotEmpty) {
        query = query.or(clauses.join(','));
      }
    }

    if (params.bhk != null) {
      if (params.bhk! >= 5) {
        query = query.gte('residentialDetails.bedrooms', 5);
      } else {
        query = query.eq('residentialDetails.bedrooms', params.bhk!);
      }
    }

    if (params.subtype != null && params.subtype!.isNotEmpty) {
      query = query.ilike('residential_subtype', '%${params.subtype}%');
    }

    if (params.postedBy != null) {
      final userTypes = switch (params.postedBy) {
        'Owner' => ['individual', 'seller'],
        'Agent' => ['broker', 'dealer', 'agent'],
        'Builder' => ['builder'],
        _ => null,
      };
      if (userTypes != null) {
        query = query.inFilter('user_profile.user_type', userTypes);
      }
    }

    // .order() returns PostgrestTransformBuilder (the parent class), not
    // PostgrestFilterBuilder — all filtering above must happen before this
    // point, since nothing after can be assigned back into `query`.
    final PostgrestTransformBuilder<PostgrestList> sortedQuery = query
        .order(params.sort.column, ascending: params.sort.ascending)
        // Deterministic tiebreaker — only needed because this method paginates
        // and the website doesn't; without it, `.range()` paging across rows
        // with duplicate sort-column values could skip or repeat results.
        .order('id', ascending: true);

    final PostgrestResponse<PostgrestList> response = includeRange
        ? await sortedQuery
              .range(offset, offset + limit - 1)
              .count(CountOption.exact)
        : await sortedQuery.limit(limit).count(CountOption.exact);

    return PropertySearchPage(
      rows: List<Map<String, dynamic>>.from(response.data),
      totalCount: response.count,
    );
  }

  /// Ports PropertyDetails.tsx's exact 3-query shape: the property row, its
  /// owner's profile (auth-aware column list — phone only when signed in),
  /// then exactly one of properties_land/_residential/_commercial branched
  /// on category. Reshapes into the same map shape the bulk query already
  /// produces so PropertyModel.fromSupabase is the single, shared parser for
  /// both fetch paths.
  Future<PropertyDetailBundle> getPropertyDetail(String propertyId) async {
    final Map<String, dynamic> propertyRow = await _supabase
        .from('properties')
        .select('*')
        .eq('id', propertyId)
        .single();

    final String? ownerUserId = propertyRow['user_id']?.toString();
    Map<String, dynamic>? profileRow;
    if (ownerUserId != null) {
      final bool isSignedIn = _supabase.auth.currentUser != null;
      final String profileColumns = isSignedIn
          ? 'display_name, avatar_url, user_type, phone, social_media, comments_enabled'
          : 'display_name, avatar_url, user_type, social_media, comments_enabled';
      profileRow = await _supabase
          .from('profiles')
          .select(profileColumns)
          .eq('user_id', ownerUserId)
          .maybeSingle();
    }

    final String? category = propertyRow['category']?.toString();
    final String? subtypeTable = switch (category) {
      'land' => 'properties_land',
      'residential' || 'pg_coliving' => 'properties_residential',
      'commercial' => 'properties_commercial',
      _ => null,
    };

    final Map<String, dynamic> mergedRow = {...propertyRow};
    if (subtypeTable != null) {
      final subtypeRow = await _supabase
          .from(subtypeTable)
          .select('*')
          .eq('property_id', propertyRow['id'])
          .maybeSingle();
      mergedRow[subtypeTable] = subtypeRow;
    }

    // Listing-specific contact override (PropertyDetails.tsx's
    // `effectiveEmail`/`effectivePhone`) — RLS on `property_contact_details`
    // already limits this row to the owner/admin/an approved inquirer for
    // email, so an unauthorized viewer simply gets no row back rather than
    // needing any check here. `contact_phone` was previously never selected
    // at all, so a seller's per-listing phone override saved correctly but
    // was never read back — the Call button always used the profile phone.
    final Map<String, dynamic>? contactRow = await _supabase
        .from('property_contact_details')
        .select('contact_email, contact_phone')
        .eq('property_id', propertyRow['id'])
        .maybeSingle();

    return PropertyDetailBundle(
      property: PropertyModel.fromSupabase(mergedRow),
      ownerProfile: profileRow != null
          ? PropertyOwnerProfile.fromSupabase(profileRow)
          : null,
      contactEmail: contactRow?['contact_email']?.toString(),
      contactPhone: contactRow?['contact_phone']?.toString(),
    );
  }

  /// Signed URLs for a Land listing's saved ownership documents
  /// (`metadata.ownershipDocumentPaths`) — the `documents` bucket has no
  /// public-read policy at all, so this is the only way to view one.
  /// Mirrors the portal's `handleViewOwnershipDocuments`
  /// (PropertyDetails.tsx): calls the same `get-property-document-url` edge
  /// function, which re-checks `properties` RLS for the caller before
  /// minting anything — this method does no authorization decision of its
  /// own, the edge function is the actual gate. Returns `(path, url)` pairs;
  /// throws the edge function's own error message on failure (no listing, no
  /// documents, access denied) so the caller can show it directly.
  Future<List<({String path, String url})>> getOwnershipDocumentUrls(
    String propertyId,
  ) async {
    final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke(
        'get-property-document-url',
        body: {'propertyId': propertyId},
      );
    } on FunctionException catch (e) {
      // The edge function always responds with a JSON `{error: "..."}` body
      // on failure (no listing/no documents/access denied) — `.details` is
      // that already-decoded body, same shape `response.data` would be on
      // success (functions_client's own invoke() decodes it either way).
      final details = e.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw message ?? 'Could not load ownership documents.';
    }
    final data = response.data;
    final documents = data is Map ? data['documents'] : null;
    if (documents is! List) {
      throw 'Could not load ownership documents.';
    }
    return [
      for (final doc in documents)
        if (doc is Map && doc['path'] is String && doc['url'] is String)
          (path: doc['path'] as String, url: doc['url'] as String),
    ];
  }

  /// Ports RelatedPropertyCards.tsx's two-tier query: narrow-select same
  /// type+category+approved+city-substring match, falling back to a
  /// broader query (dropping the city filter) only if fewer than 4 rows
  /// came back, then de-duping and capping to 6 in that fallback branch
  /// only.
  Future<List<PropertyModel>> getRelatedProperties({
    required String propertyId,
    required String propertyType,
    required String category,
    required String location,
  }) async {
    // Joins the sub-tables (same as `getPropertiesByUser`) — without them
    // `PropertyModel.fromSupabase` has no `properties_residential`/
    // `properties_commercial` row to read bedrooms/bathrooms off, so every
    // related card silently showed 0 beds/0 baths even for properties that
    // have real values.
    const columns =
        'id, title, location, price, media_urls, category, property_type, area, area_unit, status, metadata, '
        'properties_residential(bedrooms,bathrooms), properties_commercial(washrooms)';
    final cityToken = location.split(',').first.trim().toLowerCase();

    final primaryRows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('properties')
          .select(columns)
          .eq('approval_status', 'approved')
          .eq('property_type', propertyType)
          .eq('category', category)
          .neq('id', propertyId)
          .ilike('location', '%$cityToken%')
          .limit(10),
    );

    List<Map<String, dynamic>> rows = primaryRows;

    if (rows.length < 4) {
      final fallbackRows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('properties')
            .select(columns)
            .eq('approval_status', 'approved')
            .eq('property_type', propertyType)
            .eq('category', category)
            .neq('id', propertyId)
            .limit(10),
      );

      final seenIds = {for (final r in rows) r['id'].toString()};
      for (final r in fallbackRows) {
        final id = r['id']?.toString();
        if (id != null && seenIds.add(id)) {
          rows.add(r);
        }
      }
      rows = rows
          .where((r) => (r['title'] as String? ?? '').isNotEmpty)
          .toList();
      if (rows.length > 6) {
        rows = rows.sublist(0, 6);
      }
    }

    return rows.map((r) => PropertyModel.fromSupabase(r)).toList();
  }

  /// Calls the `track_property_view` RPC exactly as the website does — same
  /// param names, same server-side 30-minute dedupe semantics.
  Future<bool> trackPropertyView({
    required String propertyId,
    String? viewerUserId,
    required String viewerSessionId,
    required int viewDurationSeconds,
    required int viewPercentage,
  }) async {
    final result = await _supabase.rpc(
      'track_property_view',
      params: {
        'property_uuid': propertyId,
        'viewer_user_id': viewerUserId,
        'viewer_session_id': viewerSessionId,
        'view_duration': viewDurationSeconds,
        'view_percentage': viewPercentage,
      },
    );
    return result as bool? ?? false;
  }

  /// Live counts for the Home "Popular Categories" tiles.
  ///
  /// Mirrors `PropertyCategories.tsx`'s `countProperties` queries for the
  /// five property-side categories: same table, same `status`/
  /// `approval_status` filter, same `category`/`property_type` column
  /// split. `head: true` has no direct supabase_flutter equivalent, so each
  /// query selects just `id` and caps at 1 row — the exact total still comes
  /// back via the `count` header regardless of that cap, so this returns the
  /// same number while transferring far less than a full row set would.
  ///
  /// The reference component also counts brokers/builders/influencers/
  /// projects tiles, omitted here: this app has no "browse all" screen for
  /// those roles to navigate a tap to yet, and a tile that can't be tapped
  /// correctly is worse than one that isn't shown.
  Future<Map<String, int>> getCategoryCounts() async {
    Future<int> count({String? category, String? propertyType}) async {
      var query = _supabase
          .from('properties')
          .select('id')
          .eq('status', 'active')
          .eq('approval_status', 'approved');
      if (category != null) query = query.eq('category', category);
      if (propertyType != null) query = query.eq('property_type', propertyType);

      final response = await query.limit(1).count(CountOption.exact);
      return response.count;
    }

    final results = await Future.wait([
      count(category: 'land'),
      count(category: 'residential'),
      count(category: 'commercial'),
      count(propertyType: 'rent'),
      count(propertyType: 'sell'),
    ]);

    return {
      'land': results[0],
      'residential': results[1],
      'commercial': results[2],
      'rent': results[3],
      'sell': results[4],
    };
  }

  Future<List<AvailableLocation>> getAvailableLocations() async {
    final rows = await _supabase
        .from('available_locations')
        .select('id,city,state,country,latitude,longitude')
        .eq('is_active', true)
        // Matches the portal's own `location-lookups` edge function, which
        // filters explicitly rather than relying on every row happening to
        // already be India — an explicit guard, not a fix for data seen to
        // be wrong today.
        .eq('country', 'India')
        .order('display_order');

    return List<Map<String, dynamic>>.from(
      rows,
    ).map((r) => AvailableLocation.fromSupabase(r)).toList();
  }

  /// Calls the `global_search` RPC used for the debounced autocomplete
  /// dropdown. See GlobalSearchSuggestion.fromSupabase for why the id field
  /// is read defensively.
  Future<List<GlobalSearchSuggestion>> globalSearch(String term) async {
    final result = await _supabase.rpc(
      'global_search',
      params: {'search_term': term},
    );
    return List<Map<String, dynamic>>.from(
      result as List<dynamic>,
    ).map((r) => GlobalSearchSuggestion.fromSupabase(r)).toList();
  }

  /// Fetches raw property, sub-table, and contact rows for pre-filling the
  /// edit wizard. Mirrors SellerWall.tsx lines 372–411.
  Future<PropertyEditBundle> fetchForEdit(String propertyId) async {
    final propertyRow = await _supabase
        .from('properties')
        .select('*')
        .eq('id', propertyId)
        .single();

    final String? category = propertyRow['category']?.toString();
    final String? subtableTable = switch (category) {
      'residential' || 'pg_coliving' => 'properties_residential',
      'commercial' => 'properties_commercial',
      'land' => 'properties_land',
      _ => null,
    };

    final Map<String, dynamic>? subtableRow = subtableTable != null
        ? await _supabase
              .from(subtableTable)
              .select('*')
              .eq('property_id', propertyId)
              .maybeSingle()
        : null;

    final Map<String, dynamic>? contactRow = await _supabase
        .from('property_contact_details')
        .select('*')
        .eq('property_id', propertyId)
        .maybeSingle();

    // TEMPORARY — P0 real-device edit-hydration trace. Remove once the
    // reported bug (Portal-created listings edit blank in the app) is
    // confirmed fixed on-device. Answers: is the raw data even present in
    // what the phone fetches, before any provider/UI code touches it.
    final dynamic rawMeta = propertyRow['metadata'];
    final Map<String, dynamic> meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};
    String mask(String? s) {
      if (s == null || s.isEmpty) return '<empty>';
      if (s.length <= 4) return '***';
      return '${s.substring(0, 2)}***${s.substring(s.length - 2)}';
    }

    debugPrint('[EDIT_TRACE] ===== fetchForEdit =====');
    debugPrint('[EDIT_TRACE] supabaseUrl=${dotenv.env['SUPABASE_URL']}');
    debugPrint('[EDIT_TRACE] propertyId=$propertyId');
    debugPrint('[EDIT_TRACE] category=$category');
    debugPrint('[EDIT_TRACE] property_type=${propertyRow['property_type']}');
    debugPrint('[EDIT_TRACE] hashtags=${propertyRow['hashtags']}');
    debugPrint('[EDIT_TRACE] is_negotiable=${propertyRow['is_negotiable']}');
    debugPrint(
      '[EDIT_TRACE] metadata keys (${meta.length})=${meta.keys.toList()}',
    );
    debugPrint('[EDIT_TRACE] metadata.landSubtype=${meta['landSubtype']}');
    debugPrint('[EDIT_TRACE] metadata.landType=${meta['landType']}');
    debugPrint(
      '[EDIT_TRACE] metadata.front/back/left/right='
      '${meta['front']}/${meta['back']}/${meta['left']}/${meta['right']}',
    );
    debugPrint('[EDIT_TRACE] metadata.surveyNumber=${meta['surveyNumber']}');
    debugPrint('[EDIT_TRACE] metadata.soilType=${meta['soilType']}');
    debugPrint('[EDIT_TRACE] metadata.ownershipType=${meta['ownershipType']}');
    debugPrint('[EDIT_TRACE] metadata.ownerName=${meta['ownerName']}');
    debugPrint('[EDIT_TRACE] metadata.tokenAmount=${meta['tokenAmount']}');
    debugPrint(
      '[EDIT_TRACE] metadata.priceNegotiable=${meta['priceNegotiable']}',
    );
    debugPrint(
      '[EDIT_TRACE] metadata.allInclusivePriceToggle='
      '${meta['allInclusivePriceToggle']}, allInclusivePrice='
      '${meta['allInclusivePrice']}',
    );
    debugPrint('[EDIT_TRACE] metadata.brokerage=${meta['brokerage']}');
    debugPrint(
      '[EDIT_TRACE] metadata.furnishedType=${meta['furnishedType']}, '
      'furnishingType=${meta['furnishingType']}',
    );
    debugPrint(
      '[EDIT_TRACE] subtableTable=$subtableTable, '
      'subtableRow=${subtableRow ?? '<null — no row found>'}',
    );
    debugPrint(
      '[EDIT_TRACE] contactRow present=${contactRow != null}, '
      'phone=${mask(contactRow?['contact_phone']?.toString())}, '
      'email=${mask(contactRow?['contact_email']?.toString())}',
    );
    debugPrint('[EDIT_TRACE] ===== end fetchForEdit =====');

    return PropertyEditBundle(
      propertyRow: Map<String, dynamic>.from(propertyRow),
      subtableRow: subtableRow != null
          ? Map<String, dynamic>.from(subtableRow)
          : null,
      contactRow: contactRow != null
          ? Map<String, dynamic>.from(contactRow)
          : null,
    );
  }

  /// Deletes a property row by ID. Sub-tables rely on ON DELETE CASCADE or are
  /// left orphaned (same behavior as the React dashboard delete flow).
  Future<void> deleteProperty(String propertyId) async {
    await _supabase.from('properties').delete().eq('id', propertyId);
  }

  /// Flips one listing's `status`, the way the dashboard's inline picker does on
  /// the website (BrokerContentManager.tsx:85-112: a bare
  /// `update({ status }).eq('id', …)`, nothing else in the payload).
  ///
  /// Appended rather than folded into [updateProperty] on purpose. That method
  /// documents "does NOT touch status" and rebuilds the whole row from a
  /// [PostPropertyProvider]; a status flip has no provider and must not disturb
  /// media, metadata or the sub-tables. No existing method, signature or caller
  /// changes as a result of this one.
  ///
  /// [status] is deliberately not validated here: the caller picks from
  /// [propertyStatusOptions], and the column's own CHECK is the real authority.
  /// The `updated_at` trigger fires on its own — the website does not set it
  /// either.
  ///
  /// RLS restricts the UPDATE to `auth.uid() = user_id`, so a non-owner's call
  /// matches no row and completes silently, exactly as it does on the website.
  Future<void> setPropertyStatus(String propertyId, String status) async {
    await _supabase
        .from('properties')
        .update({'status': status})
        .eq('id', propertyId);
  }

  /// Updates an existing property listing. Mirrors the React PropertyWizard
  /// edit-submission path (PropertyWizard.tsx lines 1741–1909).
  /// - Uploads any newly-added media items and combines with existing URLs.
  /// - Does NOT touch [status], [user_id], or [amenities] — preserves existing.
  Future<void> updateProperty(
    String propertyId,
    PostPropertyProvider provider,
    String userId,
  ) async {
    // Re-queue for review first (non-admin owners), like the website.
    await resubmitForApproval(
      _supabase,
      table: 'properties',
      id: propertyId,
    );
    final List<String> newUrls = await _uploadMedia(provider, userId);
    final List<String> allUrls = [...provider.existingMediaUrls, ...newUrls];

    // Non-destructive update: merge onto the row's existing metadata instead
    // of replacing the column, mirroring React's
    // `const metadata = { ...editingProperty.metadata }`
    // (PropertyWizard.tsx:1561).
    //
    // Without this, any key the Flutter form does not currently collect —
    // nested objects like `buildingInventory`, the PG block, land legal
    // flags — was silently dropped the first time a listing was edited in
    // the app. Nested objects are deliberately preserved here rather than
    // hydrated into the provider; full editing support for them lands with
    // the category parity phases.
    final Map<String, dynamic> existingMetadata = await _fetchExistingMetadata(
      propertyId,
    );
    final Map<String, dynamic> metadata = _fillTypedEmpties(
      _applyProjectTag(<String, dynamic>{
        ...existingMetadata,
        ..._buildMetadata(provider),
      }, provider),
    );

    // Append rather than overwrite — the wizard never re-hydrates a saved
    // document back into `provider.ownershipDocuments` (same as the portal's
    // own LegalDetailsStep), so a fresh upload here must be added onto
    // whatever's already saved, never replace it.
    final List<String> newOwnershipDocumentPaths =
        await _uploadOwnershipDocuments(provider, userId);
    if (newOwnershipDocumentPaths.isNotEmpty) {
      final existingPaths = existingMetadata['ownershipDocumentPaths'];
      final List<String> previous = existingPaths is List
          ? existingPaths.map((p) => p.toString()).toList()
          : const [];
      metadata['ownershipDocumentPaths'] = [
        ...previous,
        ...newOwnershipDocumentPaths,
      ];
    }

    await _supabase
        .from('properties')
        .update({
          'title': provider.title,
          'description': provider.description,
          'location': provider.location,
          'latitude': provider.latitude,
          'longitude': provider.longitude,
          'price': _headlinePrice(provider),
          'area': provider.area.isEmpty ? '0' : provider.area,
          'area_unit': provider.areaUnit.isEmpty
              ? 'sq_ft'
              : canonicalAreaUnit(provider.areaUnit),
          'rate_per_area': double.tryParse(provider.ratePerArea),
          'available_from': _availableFrom(provider),
          'hashtags': _parseHashtags(provider.hashtags),
          'amenities': provider.listVal('amenities'),
          'media_urls': allUrls,
          'main_display_media_url': _mainDisplayUrl(provider, allUrls),
          'property_type':
              (provider.listingIntent ??
                      (throw StateError('Listing intent must be selected.')))
                  .name,
          'category': _categoryToDb(
            provider.category ??
                (throw StateError('Property category must be selected.')),
          ),
          // React writes this key unconditionally, using '' for every non-
          // residential category (PropertyWizard.tsx:1784). Omitting it left the
          // nullable column NULL, which breaks the dbSafe rule that nothing
          // reaches Postgres as NULL except dates and FKs — and any web reader
          // doing `.trim()` on it would throw.
          'residential_subtype':
              provider.category == PropertyCategory.residential
              ? canonicalResidentialSubtype(provider.residentialSubType ?? '')
              : '',
          // null, never '' — the column is a uuid FK to builder_projects, so a
          // placeholder would fail the constraint (React uses dbUuid for this).
          'project_id': provider.projectId.isEmpty ? null : provider.projectId,
          // See the matching comment in _insertProperty — real column, not
          // just `metadata.priceNegotiable`.
          'is_negotiable': provider.priceNegotiable,
          'metadata': metadata,
        })
        .eq('id', propertyId);

    await _upsertCategoryData(propertyId, provider);
    await _upsertContactDetails(propertyId, provider);
  }

  // ── Builder project tag (T5) ──────────────────────────────────────────
  //
  // Tag only: searching and attaching an existing project. Creating projects
  // and the inventory subsystem stay React-only by decision.

  /// Attaches the builder/company name to each project.
  ///
  /// `builder_projects` has no FK to `profiles`, so React resolves the names in
  /// a second query rather than embedding them
  /// (ProjectTagSelector.tsx:35). Company name wins over display name.
  Future<List<TaggedProject>> _withBuilderNames(
    List<TaggedProject> projects,
  ) async {
    final ids = projects
        .map((p) => p.builderId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return projects;

    final rows = await _supabase
        .from('profiles_public')
        .select('user_id, display_name, company_name')
        .inFilter('user_id', ids.toList());

    final nameById = <String, String>{
      for (final r in List<Map<String, dynamic>>.from(rows))
        r['user_id']
            .toString(): (r['company_name']?.toString().isNotEmpty ?? false)
            ? r['company_name'].toString()
            : (r['display_name']?.toString() ?? ''),
    };

    return projects
        .map((p) => p.copyWith(builderName: nameById[p.builderId]))
        .toList();
  }

  /// Projects a listing may be tagged to.
  ///
  /// Mirrors ProjectTagSelector.tsx:130 exactly: active + approved only; a
  /// search term of 2+ characters matches title or location, otherwise the
  /// listing's city is used to suggest nearby projects; newest first, capped
  /// at 12.
  ///
  /// Note this is NOT restricted to the signed-in user's own projects — the
  /// migration specification says otherwise (PHASE 4), but React is the
  /// authority and the feature exists so a broker can tag a *developer's*
  /// project.
  Future<List<TaggedProject>> searchBuilderProjects({
    String term = '',
    String city = '',
  }) async {
    var request = _supabase
        .from('builder_projects')
        .select(TaggedProject.columns)
        .eq('status', 'active')
        .eq('approval_status', 'approved');

    final trimmed = term.trim();
    if (trimmed.length >= 2) {
      final escaped = trimmed.replaceAll(RegExp(r'[%,]'), ' ');
      request = request.or('title.ilike.%$escaped%,location.ilike.%$escaped%');
    } else if (city.isNotEmpty) {
      request = request.ilike('location', '%$city%');
    }

    final rows = await request.order('created_at', ascending: false).limit(12);

    return _withBuilderNames(
      List<Map<String, dynamic>>.from(
        rows,
      ).map(TaggedProject.fromSupabase).toList(),
    );
  }

  /// Loads a single tagged project, for showing the chip when editing an
  /// already-tagged listing. Mirrors `fetchTaggedProject`.
  Future<TaggedProject?> fetchTaggedProject(String projectId) async {
    if (projectId.isEmpty) return null;
    final row = await _supabase
        .from('builder_projects')
        .select(TaggedProject.columns)
        .eq('id', projectId)
        .maybeSingle();
    if (row == null) return null;

    final resolved = await _withBuilderNames([TaggedProject.fromSupabase(row)]);
    return resolved.first;
  }

  /// The value written to the `price` column.
  ///
  /// PG / co-living never fills the single price box — PricingStep asks for
  /// per-bed / per-room rent, or a total sale price. React mirrors whichever
  /// applies into `price` so cards, search filters and sorting see a real
  /// amount (PropertyWizard.tsx:1746); without it every app-created PG listing
  /// renders as "Price on Request" and sorts as though it were free.
  ///
  /// `properties.price` is `text NOT NULL`, so this never returns null and
  /// falls back to '0' exactly as React's `dbText(headlinePrice || price, '0')`
  /// does.
  static String _headlinePrice(PostPropertyProvider provider) {
    String result = provider.price;

    if (provider.category == PropertyCategory.pg) {
      switch (provider.listingIntent) {
        case ListingIntent.sell:
          result = provider.text('totalSalePrice');
        case ListingIntent.rent:
          final perBed = provider.text('monthlyRentPerBed');
          result = perBed.isNotEmpty
              ? perBed
              : provider.text('monthlyRentPerRoom');
        case ListingIntent.lease:
        case null:
          result = provider.price;
      }
    }

    if (result.trim().isEmpty) result = provider.price;
    return result.trim().isEmpty ? '0' : result;
  }

  /// `available_from` as React stores it: the literal 'Immediately', or a
  /// plain `YYYY-MM-DD` date — never a full ISO-8601 timestamp.
  ///
  /// The column is text and React's input is `<input type="date">`, so writing
  /// `toIso8601String()` put `2026-07-31T00:00:00.000` where the web expects
  /// `2026-07-31`. React defaults the column to 'Immediately' when unset.
  static String _availableFrom(PostPropertyProvider provider) {
    final DateTime? d = provider.availableFrom;
    if (d == null) return 'Immediately';
    final String mm = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// The listing's main image: the photo the user starred, or the first one.
  ///
  /// Mirrors `dbText(formData.mainDisplayMediaUrl, allMediaUrls[0] ?? '')`
  /// (PropertyWizard.tsx:1773) — never null, empty only when there are no
  /// photos at all. The starred URL is ignored if it is no longer among the
  /// listing's media, which happens when the user removes the starred photo
  /// and saves without picking another.
  static String _mainDisplayUrl(
    PostPropertyProvider provider,
    List<String> allUrls,
  ) {
    final String starred = provider.mainDisplayMediaUrl;
    if (starred.isNotEmpty && allUrls.contains(starred)) return starred;
    return allUrls.isNotEmpty ? allUrls.first : '';
  }

  /// Reads the current `metadata` blob for [propertyId] so an edit can merge
  /// onto it rather than replace it. Returns an empty map if the row is gone
  /// or the column is null/not an object — the caller then behaves exactly as
  /// it did before, so a read failure can never make the update *more*
  /// destructive than it already was.
  Future<Map<String, dynamic>> _fetchExistingMetadata(String propertyId) async {
    final row = await _supabase
        .from('properties')
        .select('metadata')
        .eq('id', propertyId)
        .maybeSingle();

    final dynamic meta = row?['metadata'];
    return meta is Map ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
  }

  /// Creates a property listing on Supabase, mirroring the React
  /// PropertyWizard submission flow exactly. Returns the new property's UUID
  /// together with its real, server-assigned `approval_status` — a new
  /// listing is not necessarily `approved`/live just because the insert
  /// succeeded.
  Future<PropertyCreationResult> createProperty(
    PostPropertyProvider provider,
    String userId,
  ) async {
    await _checkApproval(userId);
    final List<String> uploadedUrls = await _uploadMedia(provider, userId);
    final List<String> ownershipDocumentPaths =
        await _uploadOwnershipDocuments(provider, userId);
    final Map<String, dynamic> metadata = _fillTypedEmpties(
      _applyProjectTag(_buildMetadata(provider), provider),
    );
    if (ownershipDocumentPaths.isNotEmpty) {
      metadata['ownershipDocumentPaths'] = ownershipDocumentPaths;
    }
    final PropertyCreationResult created = await _insertProperty(
      provider,
      userId,
      uploadedUrls,
      metadata,
    );
    await _insertCategoryData(created.propertyId, provider);
    await _insertContactDetails(created.propertyId, provider);
    return created;
  }

  /// Inserts the main `properties` row and returns its UUID plus its real
  /// `approval_status`, read back from the same insert response (no extra
  /// round trip needed to learn whether the new row is actually approved).
  Future<PropertyCreationResult> _insertProperty(
    PostPropertyProvider provider,
    String userId,
    List<String> uploadedUrls,
    Map<String, dynamic> metadata,
  ) async {
    final row = <String, dynamic>{
      'user_id': userId,
      'title': provider.title,
      'description': provider.description,
      'location': provider.location,
      'latitude': provider.latitude,
      'longitude': provider.longitude,
      'price': _headlinePrice(provider),
      'area': provider.area.isEmpty ? '0' : provider.area,
      'area_unit': provider.areaUnit.isEmpty
          ? 'sq_ft'
          : canonicalAreaUnit(provider.areaUnit),
      'rate_per_area': double.tryParse(provider.ratePerArea),
      'available_from': _availableFrom(provider),
      // React: dbArray<string>(formData.amenities) — the residential society /
      // flat / parking pickers all toggle into this one array, and it backs the
      // web's amenity filters. Flutter previously hard-coded an empty list, so
      // no app-created listing was ever findable by amenity.
      'amenities': provider.listVal('amenities'),
      'hashtags': _parseHashtags(provider.hashtags),
      'media_urls': uploadedUrls,
      'main_display_media_url': _mainDisplayUrl(provider, uploadedUrls),
      'property_type':
          (provider.listingIntent ??
                  (throw StateError(
                    'Listing intent must be selected before publishing.',
                  )))
              .name,
      'category': _categoryToDb(
        provider.category ??
            (throw StateError(
              'Property category must be selected before publishing.',
            )),
      ),
      // React writes this key unconditionally, using '' for every non-
      // residential category (PropertyWizard.tsx:1784). Omitting it left the
      // nullable column NULL, which breaks the dbSafe rule that nothing
      // reaches Postgres as NULL except dates and FKs — and any web reader
      // doing `.trim()` on it would throw.
      'residential_subtype': provider.category == PropertyCategory.residential
          ? canonicalResidentialSubtype(provider.residentialSubType ?? '')
          : '',
      'project_id': provider.projectId.isEmpty ? null : provider.projectId,
      // Real column, not just `metadata.priceNegotiable` — React writes it
      // unconditionally (PropertyWizard.tsx:1898) because every consumer that
      // filters/displays "negotiable" reads this column, not the metadata
      // copy. Omitting it left every app-created listing at the column's
      // schema default (`true`) regardless of what the user picked.
      'is_negotiable': provider.priceNegotiable,
      'metadata': metadata,
      'status': 'active',
    };

    final result = await _supabase
        .from('properties')
        .insert(row)
        .select('id, approval_status')
        .single();

    return PropertyCreationResult(
      propertyId: result['id'] as String,
      approvalStatus: result['approval_status'] as String?,
    );
  }

  /// Dispatches to the correct category sub-table INSERT based on [provider.category].
  /// Other (and null) categories have no sub-table; the call is a no-op.
  Future<void> _insertCategoryData(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    switch (provider.category) {
      case PropertyCategory.residential:
      case PropertyCategory.pg:
        await _insertResidential(propertyId, provider);
      case PropertyCategory.commercial:
        await _insertCommercial(propertyId, provider);
      case PropertyCategory.land:
        await _insertLand(propertyId, provider);
      default:
        break;
    }
  }

  /// INSERT into `properties_residential`.
  /// Used for both residential and pg categories (React does the same).
  Future<void> _insertResidential(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    await _supabase.from('properties_residential').insert({
      'property_id': propertyId,
      'bedrooms': _looseInt(provider.bedrooms),
      'bathrooms': _looseInt(provider.bathrooms),
      // React's own write is `formData.builtUpArea || formData.area`
      // (PropertyWizard.tsx:1952) — the dedicated Build Up Area field
      // (house-subtype only) wins when present, falling back to Total Area
      // for apartment subtype, which never renders a separate field for it.
      // This previously always sent `provider.area`, so a house-subtype
      // listing's Build Up Area was silently swapped for its Plot Area.
      'built_up_area_sqft': double.tryParse(
        provider.text('builtUpArea').isNotEmpty
            ? provider.text('builtUpArea')
            : provider.area,
      ),
      'carpet_area_sqft': double.tryParse(provider.carpetArea),
      'balconies': _looseInt(provider.balconies),
      // Portal rule (BasicInfoStep.tsx): furnished = value !== 'Raw', i.e.
      // both Semi- and Fully-Furnished count. The previous check for the
      // literal 'Furnished' never matched anything the dropdown can actually
      // produce, and omitted 'Fully-Furnished' entirely.
      'furnished':
          provider.furnishingType == 'Semi-Furnished' ||
          provider.furnishingType == 'Fully-Furnished',
      'parking_spaces': _looseInt(provider.coveredParking),
      'floor_number': _floorNumberFor(provider),
      'total_floors': _looseInt(provider.totalFloors),
      // The stale comment this replaced claimed "no provider field; React
      // also sends null" — both halves are wrong. The Condition step's
      // Building Age field (condition_step.dart's `_buildingAgeController`)
      // writes `buildingInventory.buildingAge`, and React's own save path
      // reads it the same way (`dbInt(formData.buildingInventory
      // ?.buildingAge)`, PropertyWizard.tsx:2009). Hardcoding null here
      // discarded that field (and any existing value) on every single
      // residential/commercial save.
      'age_of_property': _looseInt(provider.buildingInventoryText('buildingAge')),
      'facing_direction': provider.facing,
    });
  }

  /// INSERT into `properties_commercial`.
  Future<void> _insertCommercial(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    await _supabase.from('properties_commercial').insert({
      'property_id': propertyId,
      'built_up_area_sqft': double.tryParse(provider.area),
      'carpet_area_sqft': double.tryParse(provider.carpetArea),
      // 'washrooms' key confirmed in amenities_step.dart
      'washrooms': _looseInt(provider.text('washrooms')),
      // Commercial uses the 'totalParking' bag field, not the typed coveredParking
      'parking_spaces': _looseInt(provider.text('totalParking')),
      // Commercial dimensions use dedicated bag keys, not the typed floorNo/totalFloors
      'floor_number': _looseInt(provider.text('floorNumber')),
      'total_floors': _looseInt(provider.text('totalFloorsCommercial')),
      // Portal rule (BasicInfoStep.tsx): furnished = value !== 'Raw', i.e.
      // both Semi- and Fully-Furnished count. The previous check for the
      // literal 'Furnished' never matched anything the dropdown can actually
      // produce, and omitted 'Fully-Furnished' entirely.
      'furnished':
          provider.furnishingType == 'Semi-Furnished' ||
          provider.furnishingType == 'Fully-Furnished',
      // React maps guardRoom → cafeteria; defaults to false if not set in commercial UI
      'cafeteria': provider.guardRoom,
      'power_load_kw': double.tryParse(provider.text('powerLoad')) ?? 0,
      // React maps numberOfCabins → conference_rooms (a non-obvious mapping
      // called out in the architecture review, Q8).
      'conference_rooms': _looseInt(provider.text('numberOfCabins')) ?? 0,
    });
  }

  /// INSERT into `properties_land`.
  /// `properties_land` payload, mirroring React's `landData`
  /// (PropertyWizard.tsx:1896).
  ///
  /// Every column is written on every save, never conditionally: React's
  /// dbNum/dbBool/dbText coercers exist precisely so this table never carries
  /// a NULL. Flutter previously wrote only `area_sqft` and a conditional
  /// `soil_type`, leaving four columns NULL.
  ///
  /// `boundary`, `waterSource` and `roadWidth` have no input in React either —
  /// they are persisted but never collected — so they resolve to the same
  /// typed-empty values the web writes rather than being invented here.
  static Map<String, dynamic> _landRow(
    String propertyId,
    PostPropertyProvider provider,
  ) {
    return {
      'property_id': propertyId,
      'area_sqft': double.tryParse(provider.area) ?? 0,
      'boundary_wall': provider.boolVal('boundary'),
      'water_source': provider.text('waterSource'),
      'road_width_ft': double.tryParse(provider.text('roadWidth')) ?? 0,
      'soil_type': provider.text('soilType'),
      // Not collected by either wizard; 0 keeps the column populated.
      'slope_percentage': 0,
    };
  }

  Future<void> _insertLand(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    await _supabase
        .from('properties_land')
        .insert(_landRow(propertyId, provider));
  }

  /// INSERT into `property_contact_details`.
  /// Mirrors React lines 1881-1910: only inserts when at least one contact
  /// field is present. If both are empty, the call is skipped entirely.
  Future<void> _insertContactDetails(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    final phone = provider.contactPhone.trim();
    final email = provider.contactEmail.trim();
    if (phone.isEmpty && email.isEmpty) return;

    await _supabase.from('property_contact_details').insert({
      'property_id': propertyId,
      'contact_phone': phone.isNotEmpty ? phone : null,
      'contact_email': email.isNotEmpty ? email : null,
    });
  }

  /// `property-media`'s real, backend-enforced per-object ceiling (Supabase
  /// Storage's `file_size_limit` for this bucket).
  @visibleForTesting
  static const int maxPropertyMediaBytes = 50 * 1024 * 1024;

  /// `property-media`'s real, backend-enforced allow-list (Supabase
  /// Storage's `allowed_mime_types` for this bucket). Property/land videos
  /// upload uncompressed (unlike the influencer video path), so a `.mov`
  /// clip — the common default on iPhone — would otherwise reach Storage
  /// unconverted and be rejected there; checking here first turns that into
  /// a message that says why, instead of a raw storage error after the
  /// network round trip.
  @visibleForTesting
  static bool isAcceptedPropertyMediaMimeType(String mimeType) => const {
    'image/jpeg',
    'image/png',
    'image/webp',
    'video/mp4',
    'video/mpeg',
  }.contains(mimeType);

  /// Uploads every MediaItem in [provider] to the `property-media` bucket,
  /// mirroring the React upload loop (PropertyWizard.tsx lines 1471-1511).
  /// Path pattern: `{userId}/{timestamp}-{index}.{ext}`
  /// Returns the list of public URLs in the same order as the media items.
  Future<List<String>> _uploadMedia(
    PostPropertyProvider provider,
    String userId,
  ) async {
    final List<String> urls = [];
    for (int i = 0; i < provider.mediaItems.length; i++) {
      final item = provider.mediaItems[i];
      final bytes = await item.file.readAsBytes();
      final ext = item.file.name.split('.').last.toLowerCase();
      final contentType = item.file.mimeType ?? mimeFromExt(ext);

      if (!isAcceptedPropertyMediaMimeType(contentType)) {
        throw "That file's format ($ext) isn't supported. Please upload a "
            'JPEG, PNG, WebP, MP4 or MPEG file.';
      }
      if (bytes.length > maxPropertyMediaBytes) {
        throw 'That file is larger than the 50 MB limit '
            '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB).';
      }

      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}-$i.$ext';
      await _supabase.storage
          .from('property-media')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      final url = PublicMediaUrl.resolve(
        _supabase.storage.from('property-media').getPublicUrl(path),
      );
      urls.add(url);
    }
    return urls;
  }

  /// Uploads Land's "Ownership Document Upload" picks (legal_details_step.dart)
  /// to the private `documents` bucket — same bucket the portal's
  /// PropertyWizard.tsx uses for this exact field, required so
  /// `get-property-document-url` (the only read path — the bucket has no
  /// public/SELECT-by-anyone policy) can later sign these paths back.
  ///
  /// Path shape only needs to start with `$userId` to satisfy the bucket's
  /// own storage policy (`(storage.foldername(name))[1] = auth.uid()::text`,
  /// `20270420000000_create_documents_bucket.sql`) — read access is actually
  /// gated by the edge function re-checking `properties` RLS for the caller,
  /// not by anything in the path itself, so this follows this app's own
  /// `property-media` convention rather than inventing a new shape.
  ///
  /// Returns only THIS session's newly-uploaded paths — merging them onto
  /// whatever the listing already has saved is the caller's job (mirrors
  /// PropertyWizard.tsx's own "append rather than overwrite" comment).
  Future<List<String>> _uploadOwnershipDocuments(
    PostPropertyProvider provider,
    String userId,
  ) async {
    final List<String> paths = [];
    final files = provider.ownershipDocuments;
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = file.bytes;
      if (bytes == null) {
        // Shouldn't happen — the picker always passes `withData: true` — but
        // skip rather than crash the whole submission over one bad file.
        debugPrint(
          '[PropertyService] ownership document "${file.name}" had no '
          'bytes, skipped.',
        );
        continue;
      }
      final ext = file.name.split('.').last.toLowerCase();
      final path =
          '$userId/${DateTime.now().millisecondsSinceEpoch}-$i.$ext';
      await _supabase.storage
          .from('documents')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _ownershipDocumentMimeFor(ext),
            ),
          );
      paths.add(path);
    }
    return paths;
  }

  /// The Land document picker only ever offers these four extensions
  /// (legal_details_step.dart), all within the `documents` bucket's own
  /// `allowed_mime_types` allow-list.
  static String _ownershipDocumentMimeFor(String ext) => switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    _ => 'image/jpeg',
  };

  @visibleForTesting
  static String mimeFromExt(String ext) => switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    _ => 'application/octet-stream',
  };

  /// Converts the Flutter [PropertyCategory] enum to the DB category string.
  /// The only non-trivial mapping is pg → pg_coliving.
  /// Parses an integer count field that may have hydrated as a whole-number
  /// double's string form (e.g. "2.0" rather than "2") — bare `int.tryParse`
  /// returns null for that shape, since Dart's `int.tryParse` rejects a
  /// decimal point outright. This happens when Postgres/PostgREST hands back
  /// a `numeric` column rather than `int4` for the same field (see
  /// `PropertyModel.fromSupabase`'s own `(x as num?)?.toInt()` coercion
  /// comment, lines ~310-320, for first-party confirmation this shape is
  /// real) and the edit-hydration path round-trips it through a plain text
  /// controller with `.toString()`. Falls back to rounding a parsed double
  /// before giving up, so a bedroom/bathroom/parking/floor count hydrated
  /// this way doesn't silently null out on the next save.
  static int? _looseInt(String? s) {
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.round();
  }

  /// `floor_number` for a house residential subtype (Villa, Duplex, ...) —
  /// always `null`. `_houseDimensions` (property_dimensions_step.dart) has
  /// no Floor No input at all for these subtypes (a standalone house isn't
  /// "a floor within a building"), but `provider.floorNo` isn't cleared when
  /// the user switches an existing apartment listing's subtype to a house
  /// one, so without this gate the apartment's old floor number was
  /// silently carried over and saved onto a listing type that has no floor
  /// concept at all.
  static int? _floorNumberFor(PostPropertyProvider provider) {
    if (kHouseSubtypes.contains(provider.residentialSubType ?? '')) {
      return null;
    }
    return _looseInt(provider.floorNo);
  }

  /// Maps the Flutter category enum onto the `property_category` Postgres enum.
  ///
  /// Both non-obvious cases are spelled out rather than derived from
  /// `c.name`: PG is `pg_coliving`, and Other is **`others`** (plural).
  /// `PropertyCategory.other.name` is `'other'`, which is NOT a member of the
  /// enum — the DB accepts only
  /// `residential, commercial, land, pg_coliving, others` — so relying on the
  /// enum name made every "Others" listing fail at insert.
  static String _categoryToDb(PropertyCategory c) => switch (c) {
    PropertyCategory.pg => 'pg_coliving',
    PropertyCategory.other => 'others',
    _ => c.name, // residential, commercial, land
  };

  /// Parses a raw hashtag string (e.g. "#city #luxury sale") into the array
  /// format stored in the properties.hashtags column.
  /// Mirrors the React sanitizedHashtags computation: splits on whitespace,
  /// keeps tokens that start with '#', strips the leading '#'.
  static List<String> _parseHashtags(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.startsWith('#') && t.length > 1)
        .map((t) => t.substring(1))
        .toList();
  }

  /// Every bag key (`_text`/`_bool`/`_list` in [PostPropertyProvider]) that is
  /// only ever written by the Amenities step's "PG & Co-Living Amenities"
  /// card or the Condition step's "Food & Services"/"Housekeeping" cards —
  /// both rendered solely `if (isPg)` (amenities_step.dart, condition_step.dart).
  static const Set<String> _pgOnlyMetadataKeys = {
    // Room amenities (amenities_step.dart kPgRoomAmenities).
    'acPg', 'fanPg', 'tvPg', 'wifiPg', 'studyTablePg', 'chairPg',
    'wardrobePg', 'bedIncluded', 'mattressIncluded', 'curtainsPg',
    'refrigeratorPg', 'attachedBathroom', 'balconyPg',
    // Common-area amenities (kPgCommonAreaAmenities, stored as a list).
    'pgAmenities',
    // Safety & security (kPgSafetyAndSecurity).
    'cctvCoverage', 'biometricAccess', 'policeVerificationRequired',
    'visitorEntryRegister',
    // Tenant rules (kPgTenantRules).
    'studentsAllowed', 'workingProfessionalsAllowed', 'maleAllowed',
    'femaleAllowed', 'couplesAllowed', 'foreignNationalsAllowed',
    'petsAllowedPg', 'visitorsAllowedPg',
    // Food & services, housekeeping (condition_step.dart).
    'vegFoodPg', 'nonVegFoodPg', 'selfCookingAllowed', 'sharedKitchen',
    'mealsIncluded', 'breakfastItems', 'lunchItems', 'dinnerItems',
    'teaSnacksItems', 'laundryService', 'cleaningService', 'dailyCleaning',
    'roomCleaningFrequency', 'linenChangeFrequency',
    // PG owner contact + charges (media_contact_step.dart, pricing_step.dart).
    'ownerManagerName', 'foodCharges', 'laundryCharges',
    // Basic Info's `_pgFields` (basic_info_step.dart) — only rendered
    // `if (provider.category == PropertyCategory.pg)`. Missing from this
    // set let a Land/Residential/Commercial/Other listing that had briefly
    // been PG earlier in the same wizard session keep showing e.g.
    // "Property Status" on its public detail page under "Basic
    // Information", the same leak this set already prevents for the
    // amenity/food/tenant-rule keys above.
    'pgPropertyType', 'buildingType', 'pgPropertyName', 'propertyStatus',
  };

  /// Builds the metadata JSONB object mirroring the React PropertyWizard
  /// metadata construction (PropertyWizard.tsx lines 1502-1711).
  /// Only fields that have a matching provider getter are included.
  Map<String, dynamic> _buildMetadata(PostPropertyProvider provider) {
    final meta = <String, dynamic>{};

    // ── Category-specific long-tail bag fields ────────────────────────────
    // Commercial/Land/PG fields are stored in typed bags keyed by the same
    // React field names. Spread all three bags — JSONB accepts them all.
    //
    // Flushed FIRST, before the named writes below, so that on a key
    // collision the named field wins. This ordering matters now that edit
    // mode hydrates the metadata blob back into the bag
    // (`PostPropertyProvider.initFromRawData`): a stale bag entry carrying
    // the value loaded from the DB must not overwrite the fresh value the
    // user just typed into the field that owns that key.
    meta.addAll(provider.allTextFields);
    meta.addAll(provider.allBoolFields);
    for (final entry in provider.allListFields.entries) {
      meta[entry.key] = entry.value;
    }

    // The bag above is flat and shared across every category — switching
    // `provider.category` never clears a previous category's entries out of
    // it (see `PostPropertyProvider.setCategory`). React only ever writes
    // these PG keys into metadata when the wizard's category is PG
    // (PropertyWizard.tsx:1762, gated fillMetadata call); mirror that gate
    // here, or a listing switched PG → Land/Residential/Commercial/Other
    // before publishing keeps its PG amenities/food/tenant-rule selections
    // baked into the saved metadata and they resurface on the listing's
    // detail page under the wrong category.
    if (provider.category != PropertyCategory.pg) {
      for (final key in _pgOnlyMetadataKeys) {
        meta.remove(key);
      }
    }
    // `ratePerAreaUnit` (the Pricing step's rate unit, e.g. "sq_yards") is
    // kept in the flushed bag: React persists it to metadata too
    // (PropertyWizard.tsx fillMetadata ['ratePerAreaUnit']), and the details
    // page reads it to label the rate. Stripping it here made every
    // app-created rate show as "per Sq. Ft" regardless of the chosen unit.

    // ── Step 1: Basic Info overflow ─────────────────────────────────────────
    // React's canonical key is 'furnishedType' (BasicInfoStep's Furnishing
    // Type select, PropertyWizard.tsx:884) — this was previously never
    // written at all, so `_fillTypedEmpties` forced it to '' on every save
    // and the web edit form showed the Furnishing Type dropdown blank for
    // every Flutter-created/edited listing.
    if (provider.furnishingType != null &&
        provider.furnishingType!.isNotEmpty) {
      meta['furnishedType'] = provider.furnishingType;
    }

    // ── Others ────────────────────────────────────────────────────────────
    // React stamps the original wizard category for 'others' listings
    // (PropertyWizard.tsx:1563). Note the VALUE is singular 'other' even
    // though the column enum member is plural 'others' — matched verbatim
    // rather than normalised, because web readers compare against this exact
    // string.
    if (provider.category == PropertyCategory.other) {
      meta['originalCategory'] = 'other';
    }

    // ── Location overflow (no dedicated columns in properties table) ───────
    // Always written (even blank), same reasoning as `coveredParking`
    // below: `updateProperty` merges this map onto the listing's EXISTING
    // metadata (`{...existingMetadata, ..._buildMetadata(provider)}`). An
    // `isNotEmpty`-guarded write here meant clearing one of these fields in
    // the edit wizard produced no key at all in the fresh map, so the merge
    // left the OLD value from `existingMetadata` in place — the field
    // silently un-cleared itself the moment the edit was saved.
    meta['city'] = provider.city;
    meta['state'] = provider.state;
    meta['pincode'] = provider.pincode;
    meta['landmark'] = provider.landmark;

    // ── Carpet area / total floors — also mirrored into metadata ───────────
    // Both already have a typed column (`carpet_area_sqft`/`total_floors` on
    // `properties_residential`/`_commercial`), written in
    // `_insertResidential`/`_insertCommercial`/`_insertLand`. React writes
    // them into metadata too, on every save regardless of category
    // (PropertyWizard.tsx's "Common extra fields" `carpetArea` and the
    // catch-all `totalFloors`) — and its own edit-wizard hydration falls
    // back to `metadata.carpetArea`/`metadata.totalFloors` when the typed
    // column comes back empty. Flutter never wrote either key, so a
    // PG/Co-living listing created here — whose typed-column read path the
    // web apparently doesn't hit reliably — showed both fields as unfilled
    // on the website even though the value was saved correctly in the
    // typed column.
    if (provider.carpetArea.isNotEmpty)
      meta['carpetArea'] = provider.carpetArea;
    if (provider.totalFloors.isNotEmpty) {
      meta['totalFloors'] = provider.totalFloors;
    }

    // ── Step 4: Condition ─────────────────────────────────────────────────
    if (provider.propertyCondition != null) {
      meta['propertyCondition'] = provider.propertyCondition;
    }
    if (provider.constructionAge != null) {
      meta['constructionAge'] = provider.constructionAge;
    }
    if (provider.availabilityStatus != null) {
      meta['availabilityStatus'] = provider.availabilityStatus;
    }
    if (provider.availableItems.isNotEmpty) {
      meta['availableItems'] = provider.availableItems;
    }

    // ── Step 5: Amenities ─────────────────────────────────────────────────
    if (provider.electricityBackup != null) {
      meta['electricityBackup'] = provider.electricityBackup;
    }
    if (provider.waterAvailability != null) {
      meta['waterAvailability'] = provider.waterAvailability;
    }
    if (provider.numberOfLifts.isNotEmpty) {
      meta['numberOfLifts'] = provider.numberOfLifts;
    }
    if (provider.openParking.isNotEmpty) {
      meta['openParking'] = provider.openParking;
    }
    // Commercial Covered Parking → metadata.coveredParking, where the portal
    // writes and reads it. Always written (even blank) so clearing the field
    // replaces a stale value instead of leaving it in place.
    if (provider.category == PropertyCategory.commercial) {
      meta['coveredParking'] = provider.coveredParking;
    }
    // Booleans always included (default false is meaningful)
    meta['gasPipeline'] = provider.gasPipeline;
    meta['internetAvailability'] = provider.internetAvailability;
    // Portal's real key is `solarBackup` — see the hydration-side comment in
    // post_property_provider.dart for why this was previously `solarPower`.
    meta['solarBackup'] = provider.solarPower;
    meta['guardRoom'] = provider.guardRoom;

    // ── Step 6: Legal ─────────────────────────────────────────────────────
    meta['reraRegistered'] = provider.reraRegistered;
    if (provider.reraNumber.isNotEmpty)
      meta['reraNumber'] = provider.reraNumber;
    meta['saleDeed'] = provider.saleDeed;
    meta['registryCopy'] = provider.registryCopy;
    meta['nocAvailable'] = provider.nocAvailable;
    meta['encumbranceFree'] = provider.encumbranceFree;
    meta['loanApproved'] = provider.loanApproved;
    meta['propertyApproved'] = provider.propertyApproved;
    if (provider.facing != null) meta['facing'] = provider.facing;
    if (provider.approvedByBanks.isNotEmpty) {
      meta['approvedByBanks'] = provider.approvedByBanks;
    }

    // ── Step 7: Pricing overflow ──────────────────────────────────────────
    if (provider.securityDeposit.isNotEmpty) {
      meta['securityDeposit'] = provider.securityDeposit;
    }
    // React's canonical key is 'maintenanceCharges' — it is the live input in
    // PricingStep.tsx (bound via handleInputChange('maintenanceCharges')).
    // React's 'maintenanceAmount' is a legacy carry-through field with no UI
    // input anywhere in the wizard; writing there made the web's Maintenance
    // Charges box read empty for Flutter-created listings.
    if (provider.maintenanceCharges.isNotEmpty) {
      meta['maintenanceCharges'] = provider.maintenanceCharges;
    }
    // 'tokenAmount' IS React's canonical key (live input in PricingStep.tsx);
    // only the Flutter-side field is named bookingAmount. Correct as-is.
    if (provider.bookingAmount.isNotEmpty) {
      meta['tokenAmount'] = provider.bookingAmount;
    }
    if (provider.lockInPeriod != null)
      meta['lockInPeriod'] = provider.lockInPeriod;
    meta['priceNegotiable'] = provider.priceNegotiable;
    // React's canonical key is 'allInclusivePriceToggle'. The previous
    // 'allInclusivePrice' appears nowhere in the React source (0 occurrences
    // repo-wide), so the web could never read it.
    meta['allInclusivePriceToggle'] = provider.allInclusivePriceToggle;
    meta['taxGovtChargesIncluded'] = provider.taxGovtChargesIncluded;
    meta['loanAvailability'] = provider.loanAvailability;
    if (provider.brokerage.isNotEmpty) meta['brokerage'] = provider.brokerage;

    // ── Step 8: Contact overflow ──────────────────────────────────────────
    if (provider.contactName.isNotEmpty)
      meta['contactName'] = provider.contactName;
    if (provider.whatsappNumber.isNotEmpty) {
      meta['whatsappNumber'] = provider.whatsappNumber;
    }
    if (provider.bestTimeToCall.isNotEmpty) {
      meta['bestTimeToCall'] = provider.bestTimeToCall;
    }

    // ── Category-specific typed fields ────────────────────────────────────
    if (provider.category == PropertyCategory.residential) {
      if (provider.bhkType != null) meta['bhkType'] = provider.bhkType;
    }
    if (provider.category == PropertyCategory.pg) {
      meta['isPg'] = true;
      // React always writes this nested object, with dbBool(...) coercing every
      // unset flag to false (PropertyWizard.tsx:1649), so downstream readers
      // can index into it unconditionally. None of the seven flags has an
      // input in either wizard — they are persisted but never collected — so
      // they resolve to false rather than being invented here.
      meta['pgHouseRules'] = <String, dynamic>{
        for (final entry in _kPgHouseRuleSources.entries)
          entry.key: provider.boolVal(entry.value),
      };
      // React always writes this array too (dbArray semantics — PropertyWizard
      // .tsx), rebuilt from the Total Floors x per-floor Total Rooms/Room Type
      // inputs (see PostPropertyProvider.setFloorTotalRooms/setFloorRoomType).
      // Scoped to PG the same way pgHouseRules/isPg are above: this key is a
      // list of objects, so writing it for any other category — where this
      // editor never ran — would stomp whatever the metadata merge would
      // otherwise have preserved there.
      meta['floorWiseRoomDetails'] = provider.floorWiseRoomDetails;
    }

    // ── Commercial building inventory ─────────────────────────────────────
    // React writes this on EVERY save as dbJson(...) — always an object, never
    // undefined, so downstream readers can index into it
    // (PropertyWizard.tsx:1733). Merged over whatever is already stored so the
    // floor-wise and company-wise blocks the app cannot edit survive intact.
    meta['buildingInventory'] = <String, dynamic>{
      ...provider.buildingInventory,
    };

    // ── Media categories ──────────────────────────────────────────────────
    // Parallel array to `media_urls`, so it must be assembled in the SAME
    // order: existing photos first, then newly uploaded ones. React builds it
    // as [...existingMediaUrls.category, ...mediaFiles.category]
    // (PropertyWizard.tsx:1725).
    //
    // Flutter previously wrote only the new items' categories, so editing a
    // listing with existing photos shifted every category by the number of
    // existing images — re-labelling the wrong pictures — and dropped the
    // trailing ones (final-architecture-review NEW-5).
    meta['mediaCategories'] = <String>[
      ...provider.existingMedia.map((m) => m.category),
      ...provider.mediaItems.map((m) => m.category),
    ];

    return meta;
  }

  /// Applies the builder-project tag to an already-merged metadata blob.
  ///
  /// Verbatim port of PropertyWizard.tsx:1597 — note it DELETES keys when the
  /// listing is untagged rather than blanking them.
  ///
  /// **Must run AFTER the merge with the existing blob, never inside
  /// [_buildMetadata].** Removing a key from the freshly built map accomplishes
  /// nothing: `{...existing, ...fresh}` copies `projectId` straight back out of
  /// the stored blob, so clearing a tag in the app would silently not stick.
  /// Same ordering hazard as [_fillTypedEmpties], for the same reason.
  static Map<String, dynamic> _applyProjectTag(
    Map<String, dynamic> meta,
    PostPropertyProvider provider,
  ) {
    if (provider.projectId.isNotEmpty) {
      meta['projectId'] = provider.projectId;
      if (provider.projectName.isNotEmpty) {
        meta['projectName'] = provider.projectName;
      }
      if (provider.builderName.isNotEmpty) {
        meta['builderName'] = provider.builderName;
      }
      if (provider.projectLocation.isNotEmpty) {
        meta['projectLocation'] = provider.projectLocation;
      }
    } else {
      meta.remove('projectId');
      meta.remove('projectLocation');
      if (provider.projectName.isNotEmpty) {
        meta['projectName'] = provider.projectName;
      } else {
        meta.remove('projectName');
      }
      if (provider.builderName.isNotEmpty) {
        meta['builderName'] = provider.builderName;
      } else {
        meta.remove('builderName');
      }
    }
    return meta;
  }

  /// Writes a typed-empty value for every allow-list key still absent, so the
  /// key always exists in the blob (final-architecture-review NEW-4).
  ///
  /// React's `fillMetadata` writes each listed key unconditionally, so a
  /// web-created row has `metadata.someField = ''`. Flutter previously omitted
  /// blanks entirely, so any web reader doing `metadata.foo.trim()` rather than
  /// `metadata.foo?.trim()` would throw on an app-created listing.
  ///
  /// `''` is the right default rather than `false`/`[]`: React's
  /// `getInitialFormData()` returns roughly twenty fields, leaving every other
  /// `PropertyFormData` key `undefined`, and `fillMetadata` sends anything that
  /// is not a bool/array/object through `dbText`, which yields `''`.
  ///
  /// **Call this LAST — after the merge with any existing blob, never inside
  /// [_buildMetadata].** `putIfAbsent` then physically cannot overwrite a value
  /// that is already there. Filling before the merge would blank every key the
  /// provider does not carry, and the provider deliberately does not carry
  /// non-scalar values: nested objects (`buildingInventory`, `pgHouseRules`)
  /// and arrays of objects (`floorWiseRoomDetails`) are excluded from the bag
  /// so they round-trip intact. Blanking those and merging would re-create the
  /// exact data destruction Phase 0 fixed.
  ///
  /// Ordering it this way also means no hand-maintained list of non-scalar keys
  /// has to stay in sync — a list that would silently rot as React adds fields.
  Map<String, dynamic> _fillTypedEmpties(Map<String, dynamic> meta) {
    for (final String key in kAllReactMetadataKeys) {
      // Nested objects are still skipped outright: React writes them via
      // dbJson (an object), so '' would be the wrong type, and Flutter has no
      // value to offer for them until the category parity phases.
      if (kNestedObjectMetadataKeys.contains(key)) continue;
      // React DELETES the builder-project keys when a listing is untagged
      // (PropertyWizard.tsx:1603) instead of writing a blank, so filling them
      // here would resurrect a tag the user just cleared.
      if (kProjectTagMetadataKeys.contains(key)) continue;
      meta.putIfAbsent(key, () => '');
    }
    return meta;
  }

  /// Dispatches to the correct category sub-table write for edit mode.
  Future<void> _upsertCategoryData(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    switch (provider.category) {
      case PropertyCategory.residential:
      case PropertyCategory.pg:
        await _upsertResidential(propertyId, provider);
      case PropertyCategory.commercial:
        await _upsertCommercial(propertyId, provider);
      case PropertyCategory.land:
        await _upsertLand(propertyId, provider);
      default:
        break;
    }
  }

  /// True if [table] already has a `property_id` row for [propertyId].
  ///
  /// None of the category sub-tables (`properties_residential`,
  /// `properties_commercial`, `properties_land`, `property_contact_details`)
  /// carry a UNIQUE constraint on `property_id` — `.upsert(onConflict:
  /// 'property_id')` against them fails with Postgres 42P10 ("no unique or
  /// exclusion constraint matching the ON CONFLICT specification") the moment
  /// an edit tries to write a row that already exists. The React portal never
  /// upserts these tables either; it does exactly this select-first check
  /// before choosing `.update()` or `.insert()` (`PropertyWizard.tsx:1944-
  /// 2073`). Reproduced here rather than adding a constraint the backend was
  /// never given.
  Future<bool> _rowExists(String table, String propertyId) async {
    final existing = await _supabase
        .from(table)
        .select('id')
        .eq('property_id', propertyId)
        .maybeSingle();
    return existing != null;
  }

  Future<void> _upsertResidential(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    final data = {
      'property_id': propertyId,
      'bedrooms': _looseInt(provider.bedrooms),
      'bathrooms': _looseInt(provider.bathrooms),
      // See the matching comment in `_insertResidential` — React's own write
      // prioritises the dedicated Build Up Area field (house-subtype only)
      // over Total Area.
      'built_up_area_sqft': double.tryParse(
        provider.text('builtUpArea').isNotEmpty
            ? provider.text('builtUpArea')
            : provider.area,
      ),
      'carpet_area_sqft': double.tryParse(provider.carpetArea),
      'balconies': _looseInt(provider.balconies),
      // Portal rule (BasicInfoStep.tsx): furnished = value !== 'Raw', i.e.
      // both Semi- and Fully-Furnished count. The previous check for the
      // literal 'Furnished' never matched anything the dropdown can actually
      // produce, and omitted 'Fully-Furnished' entirely.
      'furnished':
          provider.furnishingType == 'Semi-Furnished' ||
          provider.furnishingType == 'Fully-Furnished',
      'parking_spaces': _looseInt(provider.coveredParking),
      'floor_number': _floorNumberFor(provider),
      'total_floors': _looseInt(provider.totalFloors),
      // See the matching comment in `_insertResidential` — this used to
      // hardcode null, discarding `buildingInventory.buildingAge` on every
      // edit save.
      'age_of_property': _looseInt(provider.buildingInventoryText('buildingAge')),
      'facing_direction': provider.facing,
    };
    if (await _rowExists('properties_residential', propertyId)) {
      await _supabase
          .from('properties_residential')
          .update(data)
          .eq('property_id', propertyId);
    } else {
      await _supabase.from('properties_residential').insert(data);
    }
  }

  Future<void> _upsertCommercial(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    final data = {
      'property_id': propertyId,
      'built_up_area_sqft': double.tryParse(provider.area),
      'carpet_area_sqft': double.tryParse(provider.carpetArea),
      'washrooms': _looseInt(provider.text('washrooms')),
      'parking_spaces': _looseInt(provider.text('totalParking')),
      'floor_number': _looseInt(provider.text('floorNumber')),
      'total_floors': _looseInt(provider.text('totalFloorsCommercial')),
      // Portal rule (BasicInfoStep.tsx): furnished = value !== 'Raw', i.e.
      // both Semi- and Fully-Furnished count. The previous check for the
      // literal 'Furnished' never matched anything the dropdown can actually
      // produce, and omitted 'Fully-Furnished' entirely.
      'furnished':
          provider.furnishingType == 'Semi-Furnished' ||
          provider.furnishingType == 'Fully-Furnished',
      'cafeteria': provider.guardRoom,
      // Present in _insertCommercial but missing here — every commercial
      // edit silently left these two columns frozen at their create-time
      // value (the .update() map simply never mentioned them) instead of
      // saving whatever the user has now.
      'power_load_kw': double.tryParse(provider.text('powerLoad')) ?? 0,
      'conference_rooms': _looseInt(provider.text('numberOfCabins')) ?? 0,
    };
    if (await _rowExists('properties_commercial', propertyId)) {
      await _supabase
          .from('properties_commercial')
          .update(data)
          .eq('property_id', propertyId);
    } else {
      await _supabase.from('properties_commercial').insert(data);
    }
  }

  Future<void> _upsertLand(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    final data = _landRow(propertyId, provider);
    if (await _rowExists('properties_land', propertyId)) {
      await _supabase
          .from('properties_land')
          .update(data)
          .eq('property_id', propertyId);
    } else {
      await _supabase.from('properties_land').insert(data);
    }
  }

  /// Updates or inserts `property_contact_details`. Used in edit mode.
  Future<void> _upsertContactDetails(
    String propertyId,
    PostPropertyProvider provider,
  ) async {
    final phone = provider.contactPhone.trim();
    final email = provider.contactEmail.trim();
    if (phone.isEmpty && email.isEmpty) return;

    final data = {
      'property_id': propertyId,
      'contact_phone': phone.isNotEmpty ? phone : null,
      'contact_email': email.isNotEmpty ? email : null,
    };
    if (await _rowExists('property_contact_details', propertyId)) {
      await _supabase
          .from('property_contact_details')
          .update(data)
          .eq('property_id', propertyId);
    } else {
      await _supabase.from('property_contact_details').insert(data);
    }
  }

  /// Mirrors the React PropertyWizard approval check (lines 1431-1466).
  /// Throws a human-readable String if the user is blocked or not yet approved.
  Future<void> _checkApproval(String userId) async {
    final profile = await _supabase
        .from('profiles')
        .select('approval_status, is_blocked, user_role')
        .eq('user_id', userId)
        .single();

    if (profile['is_blocked'] == true) {
      throw 'Your account has been blocked. Please contact support.';
    }

    final bool isAdmin = profile['user_role'] == 'admin';
    if (profile['approval_status'] != 'approved' && !isAdmin) {
      throw 'Your account needs to be approved before publishing properties. '
          'Current status: ${profile['approval_status'] ?? 'pending'}';
    }
  }
}
