import '../models/tool_result.dart';
import '../services/intent_stash.dart';
import 'registry.dart';

void registerSearchTools() {
  _registerSearchProperties();
  _registerCompareProperties();
}

void _registerSearchProperties() {
  toolRegistry.register(
    ToolDefinition(
      name: 'search_properties',
      description: 'Search for properties using natural-language filters.',
      execute: (params, ctx) async {
        // Store extracted filter params in IntentStash.
        // SearchResultsScreen reads IntentStash.get('va_search_filters') on initState
        // and applies them via FilterProvider.
        final filters = <String, dynamic>{};
        if (params['city'] != null) filters['city'] = params['city'];
        if (params['property_type'] != null) {
          filters['property_type'] = params['property_type'];
        }
        if (params['listing_type'] != null) {
          filters['listing_type'] = params['listing_type'];
        }
        if (params['bedrooms'] != null)
          filters['bedrooms'] = params['bedrooms'];
        if (params['min_price'] != null)
          filters['min_price'] = params['min_price'];
        if (params['max_price'] != null)
          filters['max_price'] = params['max_price'];

        IntentStash.set('va_search_filters', filters);
        ctx.navigate('/search-results');

        return ToolResult.ok();
      },
    ),
  );
}

void _registerCompareProperties() {
  toolRegistry.register(
    ToolDefinition(
      name: 'compare_properties',
      description: 'Open the property comparison screen.',
      execute: (params, ctx) async {
        ctx.navigate('/compare-properties');
        return ToolResult.ok();
      },
    ),
  );
}
