import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article_model.dart';
import '../models/article_summary.dart';

/// Read and write access to the current user's own `cms_posts` submissions.
///
/// The list method backs the Profile screen's My Content → Articles tab; the
/// fetch/create/update methods back the Article Editor (blueprint §16.9).
class ArticleService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// The seven categories offered by the web form.
  ///
  /// Copied verbatim from `CATEGORIES` in ArticleWriteForm.tsx — the column is
  /// free-text, so this list is the only thing keeping mobile submissions
  /// consistent with the web app's taxonomy. Never invent a value here.
  static const List<String> categories = [
    'Market Trends',
    'Investment Tips',
    'Legal Updates',
    'Property Guide',
    'Interior Design',
    'Finance',
    'Other',
  ];

  /// Maximum brief length, matching the web form's `maxLength={300}`.
  static const int briefMaxLength = 300;

  /// The user's own submitted articles, newest first.
  ///
  /// Mirrors ProfileDashboardShell.tsx's `fetchUserArticles` — see blueprint
  /// §9. Same table, same filter (`submitted_by`), same ordering, same
  /// 10-row limit.
  ///
  /// One deliberate difference: `approval_status` is added to the column list.
  /// React's profile query selects only `status`, but blueprint §16.4 requires
  /// the tab to surface moderation state, and the column is part of the same
  /// row — no extra round-trip, no new access.
  Future<List<ArticleSummary>> listOwn(String userId) async {
    try {
      final rows = await _supabase
          .from('cms_posts')
          .select(
            'id, title, featured_image_url, cover_image, slug, status, '
            'approval_status, created_at',
          )
          .eq('submitted_by', userId)
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(ArticleSummary.fromSupabase).toList();
    } catch (e) {
      debugPrint('ArticleService.listOwn failed: $e');
      rethrow;
    }
  }

  /// Full row for the editor.
  ///
  /// Mirrors the `loadFullArticle` effect in ArticleWriteForm.tsx, which
  /// re-fetches every column because the list view only selected a few.
  Future<ArticleModel> getById(String id) async {
    try {
      final row = await _supabase
          .from('cms_posts')
          .select('*')
          .eq('id', id)
          .single();

      return ArticleModel.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('ArticleService.getById failed: $e');
      rethrow;
    }
  }

  /// Published, approved articles for the Home "Latest Articles" rail.
  ///
  /// Mirrors the portal's home-page query (`PublicHomePage.tsx` /
  /// `AuthenticatedHomePage.tsx`, `queryKey: 'home-articles'`): same table,
  /// same two-flag filter, same `published_at` descending order, same
  /// default cap of 6. [ArticleModel] already carries every field a teaser
  /// card needs (title, slug, brief, image, category, read time, published
  /// date), so no separate display model is introduced.
  Future<List<ArticleModel>> listPublished({int limit = 6}) async {
    try {
      final rows = await _supabase
          .from('cms_posts')
          .select('*')
          .eq('status', 'published')
          .eq('approval_status', 'approved')
          .order('published_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(rows as List)
          .map((r) => ArticleModel.fromSupabase(r))
          .where((a) => a.id.isNotEmpty && a.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ArticleService.listPublished failed: $e');
      rethrow;
    }
  }

  /// Calls the `cms-posts-save` Edge Function — the same server-side write
  /// path the web portal uses for every create/update/autosave
  /// (`ArticleWriteForm.tsx`, via `backend/functions/_shared/cmsPostSave.ts`).
  ///
  /// Replaces the previous direct `cms_posts` insert/update: that path could
  /// never let an author edit an already-approved article (the RLS update
  /// policy requires `approval_status = 'pending'`, so the write would match
  /// zero rows) and had no server-side backstop if a client-side
  /// required-field check were ever bypassed. `cms-posts-save` runs as
  /// service-role, deriving author identity and the real admin/publish
  /// decision from the caller's own authenticated session — it never trusts
  /// a client-supplied admin flag for that. For a non-admin's `finalize:
  /// true` save of an already-approved article, it demotes `approval_status`
  /// back to `'pending'` in the same atomic write, requiring re-approval. A
  /// plain autosave (`finalize: false`) never touches moderation state at
  /// all, matching the web form exactly.
  ///
  /// A function that returns HTTP 200 with `{ error: '...' }` is still a
  /// failure — surfaces the server's own message rather than a generic one,
  /// same convention as `EdgeFunctionsService._invoke`.
  Future<Map<String, dynamic>> _invokeSave({
    required String? id,
    required bool finalize,
    required String title,
    required String slug,
    required String contentHtml,
    required String brief,
    required String? category,
    required List<String> tags,
    required String? imageUrl,
    required int readTime,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'cms-posts-save',
        body: {
          'id': id,
          'finalize': finalize,
          'contentType': 'article',
          'title': title,
          'brief': brief,
          'contentHtml': contentHtml,
          'category': category,
          'tags': tags,
          'featuredImageUrl': imageUrl,
          'readTime': readTime,
          'seoTitle': null,
          'seoDescription': null,
          'slug': slug,
        },
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ??
          'Could not reach the server. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Creates a new article row and returns its id.
  ///
  /// [authorName]/[authorImageUrl]/[userId]/[userType]/[isAdmin] are no
  /// longer sent to the server — `cms-posts-save` derives author identity
  /// and the admin/publish decision from the caller's own session and
  /// profile row instead. Kept as parameters only so callers (just
  /// [ArticleEditorProvider], which still needs [isAdmin] for its own
  /// pre-submit button label) don't need to change their call site.
  ///
  /// [submitForReview] false writes the draft state autosave uses for a
  /// brand-new row (`status: 'draft'`, `approval_status: 'pending'`). True
  /// applies the submit branch: admins are auto-approved and published,
  /// everyone else stays `draft` / `pending` — there is no user-facing
  /// publish in this backend.
  Future<String> create({
    required String title,
    required String slug,
    required String contentHtml,
    required String brief,
    required String? category,
    required List<String> tags,
    required String? imageUrl,
    required String authorName,
    required String? authorImageUrl,
    required int readTime,
    required String userId,
    required String? userType,
    required bool isAdmin,
    required bool submitForReview,
  }) async {
    try {
      final result = await _invokeSave(
        id: null,
        finalize: submitForReview,
        title: title,
        slug: slug,
        contentHtml: contentHtml,
        brief: brief,
        category: category,
        tags: tags,
        imageUrl: imageUrl,
        readTime: readTime,
      );
      final id = result['id']?.toString();
      if (id == null || id.isEmpty) {
        throw StateError('cms-posts-save returned no id');
      }
      return id;
    } catch (e) {
      debugPrint('ArticleService.create failed: $e');
      rethrow;
    }
  }

  /// Updates an existing article — including, now, a non-admin's edit of an
  /// already-approved one (see [_invokeSave] for exactly what that does to
  /// moderation state).
  Future<void> update({
    required String id,
    required String title,
    required String slug,
    required String contentHtml,
    required String brief,
    required String? category,
    required List<String> tags,
    required String? imageUrl,
    required String authorName,
    required String? authorImageUrl,
    required int readTime,
    required String userId,
    required String? userType,
    required bool isAdmin,
    required bool submitForReview,
  }) async {
    try {
      await _invokeSave(
        id: id,
        finalize: submitForReview,
        title: title,
        slug: slug,
        contentHtml: contentHtml,
        brief: brief,
        category: category,
        tags: tags,
        imageUrl: imageUrl,
        readTime: readTime,
      );
    } catch (e) {
      debugPrint('ArticleService.update failed: $e');
      rethrow;
    }
  }

  /// Retires an article via `soft_delete_content`, mirroring
  /// `InfluencerVideoService.softDelete`. Returns true when a row was
  /// retired, false when it was already soft-deleted or RLS matched nothing
  /// — the same contract as the portal's `softDeleteContent`, so an RLS
  /// denial cannot read as success.
  Future<bool> softDelete(String id) async {
    final result = await _supabase.rpc(
      'soft_delete_content',
      params: <String, dynamic>{'p_table': 'cms_posts', 'p_id': id},
    );
    return result == true;
  }
}
