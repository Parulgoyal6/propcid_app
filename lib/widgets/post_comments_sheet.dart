// widgets/post_comments_sheet.dart
//
// Shared comments bottom sheet for any `post_comments` row — originally
// written as a Feed-only `_FeedCommentsSheet` (`feed_screen.dart`), scoped to
// a `FeedItem`. Extracted here, parameterized by a bare `postId` instead,
// specifically so the project DETAIL page (not just its Feed card) can open
// the same thread: the Feed's project card already has a working Comment
// button (`post_comments.post_type = 'project'`), but the detail page you
// land on after tapping that same card had no comment affordance at all —
// visible on the card, missing inside the card.
//
// Behavior is unchanged from the original Feed-only version; only the
// constructor's `FeedItem item` became a plain `String postId`, since `.id`
// was the only thing ever read off it.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/reel_comment.dart';
import '../providers/auth_provider.dart';
import '../services/comment_service.dart';
import 'overlay_toast.dart';

/// Opens the comment thread for one `post_comments` row — `postId`/`postType`
/// together are that table's own scoping key (`'property'`, `'project'` or
/// `'video'`, matching whatever `post_type` value the caller's own feature
/// already uses for that row elsewhere).
void showPostCommentsSheet(
  BuildContext context, {
  required String postId,
  required String postType,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => PostCommentsSheet(postId: postId, postType: postType),
  );
}

class PostCommentsSheet extends StatefulWidget {
  const PostCommentsSheet({
    super.key,
    required this.postId,
    required this.postType,
    this.service,
  });

  final String postId;
  final String postType;

  /// Injected by tests.
  @visibleForTesting
  final CommentService? service;

  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  late final CommentService _service = widget.service ?? CommentService();
  final TextEditingController _input = TextEditingController();

  List<ReelComment>? _comments;
  bool _loadFailed = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await _service.fetchComments(
        widget.postId,
        widget.postType,
      );
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('[Comments] fetchComments failed: $e');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _submit() async {
    final content = _input.text.trim();
    if (content.isEmpty || _submitting) return;

    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to comment')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final comment = await _service.submitComment(
        postId: widget.postId,
        postType: widget.postType,
        userId: userId,
        content: content,
      );
      if (!mounted) return;
      setState(() {
        _comments = [comment, ...?_comments];
        _input.clear();
      });
    } catch (e) {
      debugPrint('[Comments] submitComment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't post comment")));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Optimistic remove + rollback on failure — mirrors the portal's
  // CombinedFeed.tsx CommentsPanel `deleteComment`.
  Future<void> _delete(ReelComment comment) async {
    // Ask first - a deleted comment cannot be brought back.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete comment?'),
        content: const Text(
          'This comment will be removed permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previous = _comments;
    setState(() {
      _comments = previous?.where((c) => c.id != comment.id).toList();
    });
    try {
      await _service.deleteComment(comment.id);
      if (mounted) showOverlayToast(context, 'Comment deleted successfully');
    } catch (e) {
      debugPrint('[Comments] deleteComment failed: $e');
      if (!mounted) return;
      setState(() => _comments = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Rides above the keyboard so the input stays visible.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text('Comments', style: AppTextStyles.heading3),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            Expanded(child: _buildBody()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load comments',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final comments = _comments;
    if (comments == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mode_comment_outlined,
              size: 56,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            Text(
              'No comments yet. Be the first!',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: comments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildCommentRow(comments[index]),
    );
  }

  /// Opens the commenter's own public profile — `comment.userId`, same
  /// pattern as the property/reel comment sheets' own commenter navigation.
  void _openCommenterProfile(String userId) {
    if (userId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': userId},
    );
  }

  Widget _buildCommentRow(ReelComment comment) {
    final name = (comment.authorName?.isNotEmpty ?? false)
        ? comment.authorName!
        : 'User';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openCommenterProfile(comment.userId),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: (comment.authorAvatarUrl?.isNotEmpty ?? false)
                ? CachedNetworkImageProvider(comment.authorAvatarUrl!)
                : null,
            child: (comment.authorAvatarUrl?.isNotEmpty ?? false)
                ? null
                : Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openCommenterProfile(comment.userId),
                child: Text(
                  name,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                comment.content,
                style: AppTextStyles.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        // Only the commenter sees the delete option — same rule as the
        // portal (and re-enforced by the `property-comments` function).
        if (comment.userId == context.read<AuthProvider>().userId)
          IconButton(
            onPressed: () => _delete(comment),
            tooltip: 'Delete comment',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
