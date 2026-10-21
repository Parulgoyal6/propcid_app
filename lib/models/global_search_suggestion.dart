// models/global_search_suggestion.dart
//
// Mirrors the `global_search` RPC's return shape, used for the search box's
// debounced autocomplete dropdown.
class GlobalSearchSuggestion {
  final String id;
  final String label;
  final String type;
  final String? description;
  final Map<String, dynamic>? metadata;

  const GlobalSearchSuggestion({
    required this.id,
    required this.label,
    required this.type,
    this.description,
    this.metadata,
  });

  // Confirmed via a live call against the production project: the deployed
  // `global_search` RPC returns `result_id`, not `id` (the migration
  // history was ambiguous on this — see git history of this comment).
  // `id` is kept as a defensive fallback only, in case a future migration
  // reverts the column name again.
  factory GlobalSearchSuggestion.fromSupabase(Map<String, dynamic> json) {
    return GlobalSearchSuggestion(
      id: (json['result_id'] ?? json['id'])?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      description: json['description']?.toString(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}
