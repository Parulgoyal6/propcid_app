import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reel_comment.dart';

/// Comments on any `post_comments`-backed content (property/video/project),
/// scoped here to reels (`post_type = 'video'`, mirroring the website's
/// ReelView.tsx: `postType={reel.type === 'influencer_video' ? 'video' :
/// 'property'}`). Uses the existing `post_comments` table — no schema change.
class CommentService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<ReelComment>> fetchComments(
    String postId,
    String postType,
  ) async {
    final rows = await _supabase
        .from('post_comments')
        .select('id,user_id,content,created_at')
        .eq('post_id', postId)
        .eq('post_type', postType)
        .order('created_at', ascending: false);

    final comments = List<Map<String, dynamic>>.from(rows);
    if (comments.isEmpty) return const [];

    final userIds = comments
        .map((c) => c['user_id'])
        .whereType<String>()
        .toSet()
        .toList();

    final Map<String, Map<String, dynamic>> profilesByUserId = {};
    if (userIds.isNotEmpty) {
      final profiles = await _supabase
          .from('profiles')
          .select('user_id,display_name,avatar_url')
          .inFilter('user_id', userIds);
      for (final p in List<Map<String, dynamic>>.from(profiles)) {
        profilesByUserId[p['user_id'] as String] = p;
      }
    }

    return comments
        .map(
          (c) => ReelComment.fromSupabase(
            c,
            profile: profilesByUserId[c['user_id']],
          ),
        )
        .toList();
  }

  Future<ReelComment> submitComment({
    required String postId,
    required String postType,
    required String userId,
    required String content,
  }) async {
    final row = await _supabase
        .from('post_comments')
        .insert({
          'post_id': postId,
          'post_type': postType,
          'user_id': userId,
          'content': content,
        })
        .select('id,user_id,content,created_at')
        .single();

    final profile = await _supabase
        .from('profiles')
        .select('user_id,display_name,avatar_url')
        .eq('user_id', userId)
        .maybeSingle();

    return ReelComment.fromSupabase(row, profile: profile);
  }

  /// Deletes one of the caller's own comments through the deployed
  /// `property-comments` Edge Function — the same call the portal's
  /// CommentsPanel makes (`{ action: 'delete', commentId }`). The function
  /// re-checks ownership server-side, so a non-owner gets a 403 with the
  /// server's own message. Throws a user-facing [String] on any failure.
  Future<void> deleteComment(String commentId) async {
    try {
      final response = await _supabase.functions.invoke(
        'property-comments',
        body: {'action': 'delete', 'commentId': commentId},
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ?? "Couldn't delete comment";
    } catch (e) {
      if (e is String) rethrow;
      throw "Couldn't delete comment";
    }
  }
}
