/// Lightweight read-only projection of a `cms_posts` row, for the Profile
/// screen's My Content → Articles tab.
///
/// Deliberately *not* the full `ArticleModel` described in blueprint §16.9 —
/// that one covers the editor's create/update payload and belongs with the
/// Article Editor workstream. This carries only the columns the list needs.
class ArticleSummary {
  final String id;
  final String title;
  final String? imageUrl;
  final String? slug;

  /// Publication state: `draft` / `published`.
  final String? status;

  /// Moderation state: `pending` / `approved` / `rejected`.
  final String? approvalStatus;

  final DateTime? createdAt;

  const ArticleSummary({
    required this.id,
    required this.title,
    this.imageUrl,
    this.slug,
    this.status,
    this.approvalStatus,
    this.createdAt,
  });

  factory ArticleSummary.fromSupabase(Map<String, dynamic> json) {
    final createdRaw = json['created_at'] as String?;

    return ArticleSummary(
      id: json['id'].toString(),
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : 'Untitled article',
      // React falls back from featured_image_url to cover_image.
      imageUrl:
          (json['featured_image_url'] as String?) ??
          (json['cover_image'] as String?),
      slug: json['slug'] as String?,
      status: json['status'] as String?,
      approvalStatus: json['approval_status'] as String?,
      createdAt: createdRaw == null ? null : DateTime.tryParse(createdRaw),
    );
  }

  /// The label shown on the list row's status chip. Moderation state wins:
  /// a published-but-pending article is still awaiting review.
  String get displayStatus {
    final approval = approvalStatus?.toLowerCase();
    if (approval == 'pending') return 'Pending review';
    if (approval == 'rejected') return 'Rejected';
    final s = status?.toLowerCase();
    if (s == 'draft') return 'Draft';
    if (s == 'published') return 'Published';
    return s == null || s.isEmpty ? 'Draft' : s;
  }
}
