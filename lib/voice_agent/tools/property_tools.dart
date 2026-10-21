import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tool_result.dart';
import '../services/intent_stash.dart';
import 'permissions.dart';
import 'registry.dart';

void registerPropertyTools() {
  _registerCreateListing();
  _registerUpdateListing();
  _registerDeleteListing();
  _registerPublishListing();
  _registerSaveDraft();
  _registerMyPropertiesSummary();
  _registerScheduleVisit();
  _registerAddImages();
}

final _supabase = Supabase.instance.client;

// ─── create_listing ───────────────────────────────────────────────────────────

void _registerCreateListing() {
  toolRegistry.register(
    ToolDefinition(
      name: 'create_listing',
      description:
          'Create a new property listing from collected slot-fill parameters.',
      execute: (params, ctx) async {
        if (ctx.userId == null) {
          return ToolResult.fail(
            'Not authenticated.',
            userMessage: "You'll need to sign in to create a listing.",
          );
        }

        // Property listings are for broker/influencer/individual — builders
        // list projects. Mirrors the website's create_listing guard
        // (listingTools.ts) so a builder gets the same friendly denial
        // instead of an RLS failure deep inside the wizard.
        if (!canCreate(CreatableContent.property, ctx.userType)) {
          return ToolResult.fail(
            'Builder accounts cannot create property listings.',
            userMessage: createDeniedMessage(CreatableContent.property),
          );
        }

        // Build title if not provided by model.
        final title = params['title'] as String? ?? _buildListingTitle(params);

        // Voice NEVER writes the listing directly. It used to insert its own
        // `properties` row here using column names that don't exist on the
        // table (deal, subtype, bedrooms, bathrooms, city, locality,
        // furnishing — the real columns are property_type, residential_subtype,
        // a single `location` field, and bedrooms/bathrooms/furnished live on
        // the properties_residential sub-table) and omitted columns the schema
        // requires (location, property_type), so the insert always threw a
        // PostgrestException — surfaced to the user as "Could not create the
        // listing. Please try again." — before a single photo could ever be
        // uploaded.
        //
        // Matching the web portal's create_listing (listingTools.ts): stash the
        // collected slots and hand off to the SAME wizard the manual "Post
        // Property" flow already uses. PostPropertyProvider + PropertyService
        // (property_service.dart) already upload photos to the `property-media`
        // bucket and insert the row correctly — reusing that proven path avoids
        // maintaining a second, drifting implementation here.
        IntentStash.set('va_listing_draft', {...params, 'title': title});
        ctx.navigate('/post-property');

        return ToolResult.ok(
          data: {'title': title},
          userMessage:
              'Got it — "$title" is ready. Opening the listing form so you can review it and add photos.',
        );
      },
    ),
  );
}

String _buildListingTitle(Map<String, dynamic> params) {
  final bedrooms = params['bedrooms'];
  final subtype = params['subtype'] as String? ?? '';
  final deal = params['deal'] as String? ?? 'sell';
  final locality = params['locality'] as String? ?? '';
  final city = params['city'] as String? ?? '';

  final bedroomsStr = bedrooms != null ? '$bedrooms BHK ' : '';
  final subtypeStr = subtype.isNotEmpty
      ? '${subtype[0].toUpperCase()}${subtype.substring(1)}'
      : 'Property';
  final dealStr = deal == 'rent'
      ? 'Rent'
      : deal == 'lease'
      ? 'Lease'
      : 'Sale';
  final locationStr = [locality, city].where((s) => s.isNotEmpty).join(', ');

  return '$bedroomsStr$subtypeStr for $dealStr${locationStr.isNotEmpty ? ' in $locationStr' : ''}';
}

// ─── update_listing ───────────────────────────────────────────────────────────

void _registerUpdateListing() {
  toolRegistry.register(
    ToolDefinition(
      name: 'update_listing',
      description: 'Update a field on one of the user\'s listings.',
      execute: (params, ctx) async {
        if (ctx.userId == null) {
          return ToolResult.fail('Not authenticated.');
        }

        final searchQuery = params['search_query'] as String? ?? '';
        final field = params['field'] as String? ?? '';
        final value = params['value'];

        if (field.isEmpty || value == null) {
          return ToolResult.fail(
            'Missing field or value.',
            userMessage:
                'Please specify which field to update and its new value.',
          );
        }

        try {
          // Find the listing by fuzzy title match.
          final found = await _supabase
              .from('properties')
              .select('id, title')
              .ilike('title', '%$searchQuery%')
              .eq('user_id', ctx.userId!)
              .limit(1)
              .maybeSingle();

          if (found == null) {
            return ToolResult.fail(
              'Listing not found.',
              userMessage:
                  "I couldn't find a listing matching \"$searchQuery\".",
            );
          }

          await _supabase
              .from('properties')
              .update({field: value})
              .eq('id', found['id'])
              .eq('user_id', ctx.userId!);

          return ToolResult.ok(
            userMessage: 'Updated $field on "${found['title']}".',
          );
        } on PostgrestException catch (e) {
          return ToolResult.fail(
            e.message,
            userMessage: 'Could not update the listing. Please try again.',
          );
        }
      },
    ),
  );
}

// ─── delete_listing ───────────────────────────────────────────────────────────

void _registerDeleteListing() {
  toolRegistry.register(
    ToolDefinition(
      name: 'delete_listing',
      description: 'Permanently delete one of the user\'s listings.',
      execute: (params, ctx) async {
        if (ctx.userId == null) {
          return ToolResult.fail('Not authenticated.');
        }

        final searchQuery = params['search_query'] as String? ?? '';

        try {
          final found = await _supabase
              .from('properties')
              .select('id, title')
              .ilike('title', '%$searchQuery%')
              .eq('user_id', ctx.userId!)
              .limit(1)
              .maybeSingle();

          if (found == null) {
            return ToolResult.fail(
              'Listing not found.',
              userMessage:
                  "I couldn't find a listing matching \"$searchQuery\".",
            );
          }

          await _supabase
              .from('properties')
              .delete()
              .eq('id', found['id'])
              .eq('user_id', ctx.userId!);

          return ToolResult.ok(
            userMessage: '"${found['title']}" has been deleted.',
          );
        } on PostgrestException catch (e) {
          return ToolResult.fail(
            e.message,
            userMessage: 'Could not delete the listing. Please try again.',
          );
        }
      },
    ),
  );
}

// ─── publish_listing ──────────────────────────────────────────────────────────

void _registerPublishListing() {
  toolRegistry.register(
    ToolDefinition(
      name: 'publish_listing',
      description: 'Publish (make active) one of the user\'s listings.',
      execute: (params, ctx) async {
        if (ctx.userId == null) {
          return ToolResult.fail('Not authenticated.');
        }

        final searchQuery = params['search_query'] as String? ?? '';
        final useLatest = params['latest'] == true;

        try {
          dynamic found;
          if (useLatest) {
            found = await _supabase
                .from('properties')
                .select('id, title')
                .eq('user_id', ctx.userId!)
                .eq('status', 'inactive')
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
          } else {
            found = await _supabase
                .from('properties')
                .select('id, title')
                .ilike('title', '%$searchQuery%')
                .eq('user_id', ctx.userId!)
                .limit(1)
                .maybeSingle();
          }

          if (found == null) {
            return ToolResult.fail(
              'Listing not found.',
              userMessage: "I couldn't find the listing to publish.",
            );
          }

          await _supabase
              .from('properties')
              .update({'status': 'active'})
              .eq('id', found['id'])
              .eq('user_id', ctx.userId!);

          return ToolResult.ok(
            userMessage: '"${found['title']}" is now published.',
          );
        } on PostgrestException catch (e) {
          return ToolResult.fail(
            e.message,
            userMessage: 'Could not publish the listing. Please try again.',
          );
        }
      },
    ),
  );
}

// ─── save_draft ───────────────────────────────────────────────────────────────

void _registerSaveDraft() {
  toolRegistry.register(
    ToolDefinition(
      name: 'save_draft',
      description: 'Save a listing as draft (set status to inactive).',
      execute: (params, ctx) async {
        if (ctx.userId == null) {
          return ToolResult.fail('Not authenticated.');
        }

        final searchQuery = params['search_query'] as String? ?? '';
        final useLatest = params['latest'] == true;

        try {
          dynamic found;
          if (useLatest) {
            found = await _supabase
                .from('properties')
                .select('id, title')
                .eq('user_id', ctx.userId!)
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
          } else {
            found = await _supabase
                .from('properties')
                .select('id, title')
                .ilike('title', '%$searchQuery%')
                .eq('user_id', ctx.userId!)
                .limit(1)
                .maybeSingle();
          }

          if (found == null) {
            return ToolResult.fail(
              'Listing not found.',
              userMessage: "I couldn't find the listing.",
            );
          }

          await _supabase
              .from('properties')
              .update({'status': 'inactive'})
              .eq('id', found['id'])
              .eq('user_id', ctx.userId!);

          return ToolResult.ok(
            userMessage: '"${found['title']}" saved as draft.',
          );
        } on PostgrestException catch (e) {
          return ToolResult.fail(
            e.message,
            userMessage: 'Could not save draft. Please try again.',
          );
        }
      },
    ),
  );
}

// ─── my_properties_summary ────────────────────────────────────────────────────

void _registerMyPropertiesSummary() {
  toolRegistry.register(
    ToolDefinition(
      name: 'my_properties_summary',
      description: 'Show the user\'s property listings.',
      execute: (params, ctx) async {
        final filter = params['filter'] as String? ?? 'all';
        ctx.navigate('/post-property?filter=$filter');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── schedule_visit ───────────────────────────────────────────────────────────

void _registerScheduleVisit() {
  toolRegistry.register(
    ToolDefinition(
      name: 'schedule_visit',
      description: 'Schedule a property visit.',
      execute: (params, ctx) async {
        final propertyName = params['property_name'] as String? ?? '';

        try {
          // Find property by name.
          final property = await _supabase
              .from('properties')
              .select('id, title')
              .ilike('title', '%$propertyName%')
              .limit(1)
              .maybeSingle();

          // Store visit context in IntentStash for the detail screen.
          IntentStash.set('va_schedule_visit', {
            'property_id': property?['id'],
            'property_name': property?['title'] ?? propertyName,
            'date': params['date'],
            'time': params['time'],
            'visitor_name': params['visitor_name'] ?? ctx.displayName,
            'visitor_phone': params['visitor_phone'],
          });

          if (property != null) {
            ctx.navigate(
              '/property-detail?propertyId=${property['id']}&action=schedule_visit',
            );
          } else {
            ctx.navigate('/search?q=${Uri.encodeComponent(propertyName)}');
          }

          return ToolResult.ok();
        } on PostgrestException catch (e) {
          return ToolResult.fail(e.message);
        }
      },
    ),
  );
}

// ─── add_images ───────────────────────────────────────────────────────────────

void _registerAddImages() {
  toolRegistry.register(
    ToolDefinition(
      name: 'add_images',
      description: 'Add images to a listing.',
      execute: (params, ctx) async {
        // `onGenerateRoute` (app.dart) matches route names verbatim and never
        // parses a query string, so a route like '/post-property?search=...'
        // never hit the '/post-property' case — it silently fell through to
        // the default (Home) route. Navigate to the plain, real route instead;
        // the user picks the listing to edit from there, same as the manual
        // "My Listings" flow.
        final listingSearch = params['listing_search'] as String? ?? '';
        if (listingSearch.isNotEmpty) {
          IntentStash.set('va_listing_search', listingSearch);
        }
        ctx.navigate('/post-property');
        return ToolResult.ok(
          userMessage: 'Opening the listing form so you can add photos.',
        );
      },
    ),
  );
}
