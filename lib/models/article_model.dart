/// A full `cms_posts` row as the editor needs it.
///
/// Distinct from [ArticleSummary], which is the trimmed projection the Profile
/// screen's My Content list uses. This carries every column the editor reads
/// or writes — see blueprint §16.9.
class ArticleModel {
  final String id;
  final String title;
  final String slug;

  /// `brief`, falling back to `excerpt` exactly as ArticleWriteForm.tsx does.
  final String brief;

  /// `content_html`, falling back to `content`. Both columns are written with
  /// the same HTML string.
  final String contentHtml;

  final String? category;
  final List<String> tags;

  /// `featured_image_url`, falling back to `cover_image`.
  final String? imageUrl;

  final int readTime;

  /// `draft` / `published`.
  final String? status;

  /// `pending` / `approved` / `rejected`.
  final String? approvalStatus;

  final String? rejectionReason;
  final String? contentType;
  final String? submittedBy;
  final bool isFeatured;
  final DateTime? publishedAt;

  /// `cms_posts.author_name` / `author_image_url` — the writer shown on the
  /// portal's article cards (`BlogCard.tsx`). Read-only display fields.
  final String? authorName;
  final String? authorImageUrl;

  const ArticleModel({
    required this.id,
    required this.title,
    required this.slug,
    this.brief = '',
    this.contentHtml = '',
    this.category,
    this.tags = const [],
    this.imageUrl,
    this.readTime = 5,
    this.status,
    this.approvalStatus,
    this.rejectionReason,
    this.contentType,
    this.submittedBy,
    this.isFeatured = false,
    this.publishedAt,
    this.authorName,
    this.authorImageUrl,
  });

  factory ArticleModel.fromSupabase(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final published = json['published_at'] as String?;

    return ArticleModel(
      id: json['id'].toString(),
      title: (json['title'] as String?) ?? '',
      slug: (json['slug'] as String?) ?? '',
      brief: (json['brief'] as String?) ?? (json['excerpt'] as String?) ?? '',
      contentHtml:
          (json['content_html'] as String?) ??
          (json['content'] as String?) ??
          '',
      category: json['category'] as String?,
      tags: rawTags is List
          ? rawTags.map((t) => t.toString()).toList()
          : const <String>[],
      imageUrl:
          (json['featured_image_url'] as String?) ??
          (json['cover_image'] as String?),
      readTime: (json['read_time'] as num?)?.toInt() ?? 5,
      status: json['status'] as String?,
      approvalStatus: json['approval_status'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      contentType: json['content_type'] as String?,
      submittedBy: json['submitted_by']?.toString(),
      isFeatured: (json['is_featured'] as bool?) ?? false,
      publishedAt: published == null ? null : DateTime.tryParse(published),
      authorName: _nonEmpty(json['author_name']),
      authorImageUrl: _nonEmpty(json['author_image_url']),
    );
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Human-readable moderation state for the editor's status banner.
  String get statusLabel {
    switch ((approvalStatus ?? 'pending').toLowerCase()) {
      case 'approved':
        return status?.toLowerCase() == 'published'
            ? 'Published — live'
            : 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending admin approval';
    }
  }
}
