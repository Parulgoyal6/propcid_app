// services/ai_search_service.dart
//
// Smart Search — calls the website's EXISTING `openai-proxy` Supabase Edge
// Function (verified live against the production project: POST
// {SUPABASE_URL}/functions/v1/openai-proxy/chat/completions, standard
// OpenAI chat-completions request/response shape, server picks the model)
// to parse a natural-language query into structured filters. No backend
// changes — this reuses the exact endpoint the website's own Smart Search
// already calls, the same way `global_search`/`track_property_view` are
// reused elsewhere in this app.
//
// The extracted filters are applied through the app's EXISTING filter/
// search pipeline (FilterProvider -> PropertyProvider.runSearch) rather
// than having the AI fetch/rank properties itself, so Smart Search can
// never bypass or duplicate the (already-fixed) search logic.
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/smart_query_result.dart';

class AiSearchService {
  static const Set<String> _validCategories = {
    'residential',
    'commercial',
    'land',
    'pg_coliving',
    'others',
  };
  static const Set<String> _validListingTypes = {'sell', 'rent', 'lease'};

  /// The real `properties.residential_subtype` vocabulary — the same list the
  /// search filter sheet offers.
  ///
  /// Deliberately NOT the website's own AI prompt vocabulary
  /// ('Apartment'|'Villa'|'Individual House'|'Kothi'). Those are loose labels,
  /// and `PropertyService` matches subtype with `ilike('%value%')` against this
  /// column, so 'Apartment' matches only 'Studio / Service Apartment' and misses
  /// 'Flat' entirely — the single most common term in the hint list below. Asking
  /// for the literal cell values makes the filter actually select rows, and keeps
  /// whatever the model returns selectable in the filter sheet too.
  static const Set<String> _validSubtypes = {
    'Flat',
    'Independent / Builder Floor',
    'Studio / Service Apartment',
    'Raw / Independent House',
    'Villa / Kothi',
    'Duplex House',
    'Triplex House',
    'Pent House',
    'Bungalow',
    'Farm House',
  };

  /// Verbatim port of the website's `SUBTYPE_HINTS`
  /// (src/features/search/SearchBarWithTags.tsx).
  ///
  /// Kept identical on purpose: it is the list that decides whether a subtype was
  /// actually named, so any divergence would make the two platforms disagree
  /// about the same sentence.
  static const List<String> _subtypeHints = [
    'apartment',
    'flat',
    'villa',
    'kothi',
    'house',
    'penthouse',
    'studio',
    'duplex',
  ];

  /// Whether [text] names a property style at all.
  ///
  /// The guard this backs exists because the model will happily infer
  /// "Apartment" from "3 BHK" — a bedroom count says nothing about whether the
  /// home is a flat, a villa or a builder floor, and accepting that inference
  /// silently excludes every other style from the results.
  static bool _mentionsSubtype(String text) {
    final String lower = text.toLowerCase();
    return _subtypeHints.any(lower.contains);
  }

  static const String _systemPrompt =
      'You are a real-estate search query parser. Extract filters from the '
      'user query and reply with ONLY compact JSON, no prose, no markdown '
      'fences: {"city": string|null, "bhk": integer|null (use 5 for "5+" or '
      '"5 or more"), "category": "residential"|"commercial"|"land"|'
      '"pg_coliving"|"others"|null, "listingType": "sell"|"rent"|"lease"|'
      'null (use "sell" for words like buy/purchase/sale), "budgetMin": '
      'number|null, "budgetMax": number|null (both in rupees — convert '
      'lakhs/crores: 1 lakh = 100000, 1 crore = 10000000), "subtype": '
      '"Flat"|"Independent / Builder Floor"|"Studio / Service Apartment"|'
      '"Raw / Independent House"|"Villa / Kothi"|"Duplex House"|'
      '"Triplex House"|"Pent House"|"Bungalow"|"Farm House"|null, '
      '"keywords": string (remaining descriptive terms not already captured '
      'above, can be an empty string)}. '
      'Set "subtype" ONLY when the query literally names a property style '
      '(flat, apartment, villa, kothi, house, penthouse, studio, duplex). '
      'Never infer it from a bedroom count: "3 BHK" means bhk=3 and subtype '
      'null, because a bedroom count does not say whether the home is a flat, '
      'a villa or a builder floor.';

  /// Parses [query] via the AI proxy. Never throws — on any failure (network
  /// error, non-200, malformed JSON), falls back to a result that just
  /// carries the original text as `keywords`, so the caller can always fall
  /// back to a plain-text search rather than being blocked.
  Future<SmartQueryResult> parseQuery(String query) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'openai-proxy/chat/completions',
        body: {
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': query},
          ],
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return SmartQueryResult(keywords: query);
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        return SmartQueryResult(keywords: query);
      }
      final message = choices.first['message'];
      final content = message is Map ? message['content'] as String? : null;
      if (content == null || content.trim().isEmpty) {
        return SmartQueryResult(keywords: query);
      }

      String cleaned = content.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```(json)?'), '').trim();
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trim();
      }

      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      final result = SmartQueryResult.fromJson(parsed);

      return SmartQueryResult(
        city: result.city,
        bhk: result.bhk,
        category: _validCategories.contains(result.category)
            ? result.category
            : null,
        listingType: _validListingTypes.contains(result.listingType)
            ? result.listingType
            : null,
        budgetMin: result.budgetMin,
        budgetMax: result.budgetMax,
        // Two gates, not one. The allow-list rejects a hallucinated or
        // loosely-worded style the way category/listingType above are already
        // filtered; `_mentionsSubtype` then rejects anything the query did not
        // actually say, which is what stops "3 BHK" becoming "Flat" even when the
        // prompt's own instruction not to infer is ignored. The model is asked to
        // behave AND checked afterwards, because a prompt is a request, not a
        // constraint.
        subtype:
            (_validSubtypes.contains(result.subtype) && _mentionsSubtype(query))
            ? result.subtype
            : null,
        keywords: result.keywords,
      );
    } catch (e) {
      // Model returned invalid JSON, the function call failed, etc. — fall
      // back to plain text rather than blocking the search.
      return SmartQueryResult(keywords: query);
    }
  }
}
