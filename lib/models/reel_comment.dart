/// One row of `post_comments` for `post_type = 'video'`, joined client-side
/// with the commenter's `profiles` row — the same two-query merge pattern
/// [ReelsService] already uses for uploader identity (no FK for Postgrest
/// to embed `post_comments.user_id -> profiles`).
class ReelComment {
  final String id;
  final String userId;
  final String content;
  final DateTime createdAt;
  final String? authorName;
  final String? authorAvatarUrl;

  const ReelComment({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.authorName,
    this.authorAvatarUrl,
  });

  factory ReelComment.fromSupabase(
    Map<String, dynamic> json, {
    Map<String, dynamic>? profile,
  }) {
    return ReelComment(
      id: json['id'].toString(),
      userId: json['user_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      authorName: profile?['display_name']?.toString(),
      authorAvatarUrl: profile?['avatar_url']?.toString(),
    );
  }
}
