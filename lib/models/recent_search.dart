// models/recent_search.dart
//
// One persisted recent-search entry.
//
// The field names are NOT an internal choice. `ai_user_memory.recent_searches`
// is a live column the React portal already reads and writes
// (src/services/rag/memoryService.ts), and the portal's voice agent feeds `q`
// straight into the model's system prompt via `buildMemoryContext()`. Both apps
// point at the same Supabase project, so writing any other shape would either
// be silently ignored by the portal or corrupt that prompt. `{q, ts}` is a
// cross-platform contract.
//
// `ts` is Unix epoch milliseconds because the portal writes `Date.now()`.
class RecentSearch {
  /// The raw query text the user submitted.
  final String q;

  /// Unix epoch milliseconds at the time the search was committed.
  final int ts;

  const RecentSearch({required this.q, required this.ts});

  /// Stamps [q] with the current time.
  factory RecentSearch.now(String q) =>
      RecentSearch(q: q, ts: DateTime.now().millisecondsSinceEpoch);

  /// Read defensively: rows written by the portal are the authority on this
  /// column's contents, and a malformed entry must degrade to a usable value
  /// rather than throw mid-render.
  factory RecentSearch.fromJson(Map<String, dynamic> json) => RecentSearch(
    q: json['q']?.toString() ?? '',
    ts: (json['ts'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'q': q, 'ts': ts};
}
