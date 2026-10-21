// models/news_item_model.dart
//
// One row of `public.news`, the admin-curated news feed shared with the web
// portal.
//
// Column list and types verified against
// `supabase/migrations/20260717120000_create_news_table.sql` plus
// `20260717130000_add_video_url_to_news.sql`, which adds the nullable
// `video_url`. Only `title` is NOT NULL; everything else may legitimately be
// absent, which is why every other field here is nullable and the card hides
// what it does not have.
class NewsItemModel {
  final String id;
  final String title;
  final String? summary;
  final String? imageUrl;
  final String? videoUrl;

  /// External "read more" target. Null for news that lives only in the app.
  final String? linkUrl;

  /// e.g. "Economic Times".
  final String? source;

  final int displayOrder;
  final DateTime publishedAt;

  const NewsItemModel({
    required this.id,
    required this.title,
    this.summary,
    this.imageUrl,
    this.videoUrl,
    this.linkUrl,
    this.source,
    required this.displayOrder,
    required this.publishedAt,
  });

  /// Parses a PostgREST row.
  ///
  /// Values are read through `toString()` rather than cast, so a column that
  /// ever changes type (or a view that returns a number where text is expected)
  /// degrades to a harmless string instead of throwing inside a list `.map`
  /// and taking the whole section down.
  factory NewsItemModel.fromSupabase(Map<String, dynamic> row) {
    return NewsItemModel(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      summary: _text(row['summary']),
      imageUrl: _text(row['image_url']),
      videoUrl: _text(row['video_url']),
      linkUrl: _text(row['link_url']),
      source: _text(row['source']),
      displayOrder: (row['display_order'] as num?)?.toInt() ?? 0,
      publishedAt:
          DateTime.tryParse(row['published_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// True when this item should render a video rather than a still.
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// True when the detail sheet should offer "Read Full Story".
  bool get hasLink => linkUrl != null && linkUrl!.isNotEmpty;

  /// Null for an absent **or** blank value.
  ///
  /// The portal's admin form writes `''` for a cleared optional field, and an
  /// empty string is falsy in the web's `{item.source && …}` guards. Dart's `??`
  /// would keep it and render an empty line, so blanks collapse to null here.
  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
