import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/article_content_converter.dart';
import '../core/utils/article_html.dart';
import '../models/article_model.dart';
import '../services/article_media_service.dart';
import '../services/article_service.dart';

/// Inline autosave status, shown subtly near the editor — never a SnackBar
/// or dialog. Mirrors the web form's own `saveStatus` (`'idle' | 'saving' |
/// 'saved'`), plus an explicit failure state the web form collapses back to
/// `'idle'` (`ArticleWriteForm.tsx`'s autosave `catch` block).
enum AutosaveStatus { idle, saving, saved, failed }

/// State for the Article Editor (blueprint §16.9).
///
/// Follows the shape of the other feature providers: a plain ChangeNotifier
/// over [ArticleService], loaded from the view's post-frame callback.
class ArticleEditorProvider extends ChangeNotifier {
  ArticleEditorProvider({
    required this.articleId,
    required this.userId,
    required this.userType,
    required this.authorName,
    required this.authorImageUrl,
    ArticleService? service,
    ArticleMediaService? mediaService,
    @visibleForTesting Duration autosaveDelay = const Duration(seconds: 30),
  }) : _service = service ?? ArticleService(),
       _mediaService = mediaService ?? ArticleMediaService(),
       _autosaveDelay = autosaveDelay;

  /// Null when composing a new article.
  final String? articleId;

  final String userId;
  final String? userType;
  final String authorName;
  final String? authorImageUrl;

  final ArticleService _service;
  final ArticleMediaService _mediaService;

  /// Stable for the life of this provider — mirrors the portal's own
  /// `draftEntityIdRef` (`useRef(crypto.randomUUID())`), a per-session id
  /// used to group a new article's uploaded images before the article has
  /// been saved and has a real id. Once [persistedId] exists, uploads use
  /// that instead so a re-opened, already-saved article keeps using its own
  /// id rather than a fresh one each time.
  final String _draftEntityId = const Uuid().v4();

  bool _imageUploading = false;

  bool get imageUploading => _imageUploading;

  /// 30 seconds in production, matching the web form's own debounce exactly
  /// (`ArticleWriteForm.tsx`'s `setTimeout(..., 30000)`). Overridable only
  /// for tests, so autosave behaviour can be verified without a real
  /// 30-second wait.
  final Duration _autosaveDelay;
  Timer? _autosaveTimer;
  AutosaveStatus _autosaveStatus = AutosaveStatus.idle;
  bool _disposed = false;

  // ── Form fields ───────────────────────────────────────────────────────────
  String title = '';
  String brief = '';

  /// HTML produced directly by the Quill rich-text editor — the same shape
  /// the web's Tiptap editor writes to `content`/`content_html`.
  String body = '';

  /// Plain-text shadow of [body], kept in step by the editor widget so
  /// emptiness checks below don't need to parse HTML.
  String bodyPlainText = '';

  String? category;
  String tags = '';
  String imageUrl = '';

  /// Manual, author-editable minutes estimate — mirrors the web form's
  /// `useState(editingArticle?.read_time || 5)` exactly. Not derived from
  /// [body]; the author sets it directly, same as propcid's number input.
  int readTime = 5;

  // ── Lifecycle state ───────────────────────────────────────────────────────
  bool _loading = false;
  bool _loadFailed = false;
  bool _saving = false;
  ArticleModel? _existing;

  /// Set once a draft has been created, so a second save updates rather than
  /// inserting — the duplicate-article guard the web form documents.
  String? _persistedId;

  bool get loading => _loading;
  bool get loadFailed => _loadFailed;
  bool get saving => _saving;
  ArticleModel? get existing => _existing;
  bool get isEditing => articleId != null;

  /// The id this draft was saved under, once a save has happened — the
  /// existing [articleId] when editing, or the id [_persist] just created.
  /// Null before the first successful save.
  String? get persistedId => _persistedId;

  /// Drives the subtle inline "Saving…" / "Draft saved" / "Autosave failed"
  /// status — never a SnackBar or dialog.
  AutosaveStatus get autosaveStatus => _autosaveStatus;

  bool get isAdmin {
    final type = userType?.toLowerCase();
    return type == 'admin' || type == 'super_admin';
  }

  /// Admins publish immediately; everyone else submits for review. The backend
  /// has no user-facing publish path, so the label must not promise one.
  String get primaryActionLabel => isAdmin ? 'Publish' : 'Submit for Review';

  List<String> get parsedTags =>
      tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  /// Mirrors the web form's submit guard: title, brief, content and category
  /// are all required.
  String? get validationError {
    if (title.trim().isEmpty) return 'Add a title.';
    if (brief.trim().isEmpty) return 'Add a brief.';
    if (bodyPlainText.trim().isEmpty) return 'Add some content.';
    if (category == null || category!.isEmpty) return 'Choose a category.';
    return null;
  }

  /// A draft needs far less — React autosaves as soon as a title and body
  /// exist.
  bool get canSaveDraft =>
      title.trim().isNotEmpty && bodyPlainText.trim().isNotEmpty && !_saving;

  bool get canSubmit => validationError == null && !_saving;

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    final id = articleId;
    if (id == null) return;

    _loading = true;
    _loadFailed = false;
    notifyListeners();

    try {
      final article = await _service.getById(id);
      _existing = article;
      _persistedId = article.id;

      title = article.title;
      brief = article.brief;
      category = article.category;
      tags = article.tags.join(', ');
      imageUrl = article.imageUrl ?? '';
      readTime = article.readTime;

      body = article.contentHtml;
      bodyPlainText = articleHtmlToDocument(article.contentHtml).toPlainText();
    } catch (e) {
      debugPrint('ArticleEditorProvider.load failed: $e');
      _loadFailed = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Field setters ─────────────────────────────────────────────────────────
  //
  // Every setter here restarts the autosave timer — the same "meaningful
  // editable change" set the web form's autosave `useEffect` dependency
  // array covers (title, brief, content, category, tags, image, read time).

  void setTitle(String value) {
    title = value;
    notifyListeners();
    _scheduleAutosave();
  }

  void setBrief(String value) {
    brief = value;
    notifyListeners();
    _scheduleAutosave();
  }

  /// [html] is the editor's current content; [plainText] its stripped-down
  /// text form, kept alongside for the emptiness checks above.
  void setBody(String html, String plainText) {
    body = html;
    bodyPlainText = plainText;
    notifyListeners();
    _scheduleAutosave();
  }

  void setCategory(String? value) {
    category = value;
    notifyListeners();
    _scheduleAutosave();
  }

  void setTags(String value) {
    tags = value;
    notifyListeners();
    _scheduleAutosave();
  }

  void setImageUrl(String value) {
    imageUrl = value;
    notifyListeners();
    _scheduleAutosave();
  }

  // ── Featured image upload ────────────────────────────────────────────────

  /// Picks an image from the device and uploads it as the featured image.
  ///
  /// Returns null on success (including a user cancellation, which is a
  /// no-op) or a message to show the user. Reuses [setImageUrl] on success,
  /// so a successful upload participates in autosave exactly like a pasted
  /// URL always has.
  Future<String?> pickAndUploadImage() async {
    if (_imageUploading) return null;

    _imageUploading = true;
    notifyListeners();
    try {
      final file = await _mediaService.pickImage();
      if (_disposed) return null;
      if (file == null) return null; // cancelled

      final url = await _mediaService.uploadImage(
        ownerId: userId,
        entityId: _persistedId ?? _draftEntityId,
        file: file,
      );
      if (_disposed) return null;
      setImageUrl(url);
      return null;
    } catch (e) {
      debugPrint('ArticleEditorProvider.pickAndUploadImage failed: $e');
      return 'Could not upload the image. Please try again.';
    } finally {
      _imageUploading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Clears the featured image — the existing URL field's own remove
  /// affordance, not a storage deletion (the object is small and unshared,
  /// same trade-off `ProfileMediaService` makes for a replaced avatar).
  void removeImage() => setImageUrl('');

  // ── Inline content image upload ──────────────────────────────────────────

  /// Picks a device photo and uploads it for insertion into the body via the
  /// Quill toolbar's image button.
  ///
  /// Returns null when the user cancels the picker — a no-op, not an error.
  /// Unlike [pickAndUploadImage], upload failures are left to propagate so
  /// the toolbar button (which drives this) can show its own message; this
  /// method doesn't touch [imageUploading] or autosave, since the resulting
  /// URL is inserted straight into the document and reaches the provider
  /// through the normal [setBody] the editor already calls on every change.
  Future<String?> pickAndUploadContentImage() async {
    final file = await _mediaService.pickImage();
    if (file == null) return null; // cancelled
    return _mediaService.uploadContentImage(
      ownerId: userId,
      entityId: _persistedId ?? _draftEntityId,
      file: file,
    );
  }

  /// Mirrors the web form's `setReadTime(parseInt(e.target.value) || 5)` —
  /// an unparsable or zero value falls back to 5 rather than being rejected.
  void setReadTime(int value) {
    readTime = value == 0 ? 5 : value;
    notifyListeners();
    _scheduleAutosave();
  }

  // ── Autosave ──────────────────────────────────────────────────────────────

  /// (Re)starts the debounce — cancelling any timer already waiting, exactly
  /// like the web form's `clearTimeout`/`setTimeout` pair.
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, _autosave);
  }

  Future<void> _autosave() async {
    if (_disposed) return;
    // Same gate as the web form's `if (!title || !contentHtml) return;`.
    if (title.trim().isEmpty || bodyPlainText.trim().isEmpty) return;
    // Never on top of an in-flight save — whether that in-flight save is a
    // previous autosave or a manual Save Draft/Submit. `_persist` itself
    // also refuses to run while `_saving`, but checking here first avoids
    // flipping the status to "saving" for an attempt that is about to
    // no-op anyway. Autosave always saves with `submitForReview: false`
    // (see below), which never touches moderation state even for an
    // approved article — matching the web form exactly.
    if (_saving) return;

    _autosaveStatus = AutosaveStatus.saving;
    notifyListeners();

    // Reuses `_persist` exactly as the manual Save Draft button does —
    // same create-vs-update id tracking, same preserved slug, same
    // `submitForReview: false` (autosave must never finalize/publish).
    final error = await _persist(submitForReview: false);
    if (_disposed) return;

    _autosaveStatus = error == null
        ? AutosaveStatus.saved
        : AutosaveStatus.failed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autosaveTimer?.cancel();
    super.dispose();
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  /// Saves without changing moderation state. Returns null on success or a
  /// message to show the user.
  Future<String?> saveDraft() => _persist(submitForReview: false);

  /// Submits for review (or publishes, for an admin).
  Future<String?> submit() {
    final invalid = validationError;
    if (invalid != null) return Future.value(invalid);
    return _persist(submitForReview: true);
  }

  Future<String?> _persist({required bool submitForReview}) async {
    if (_saving) return null;

    _saving = true;
    notifyListeners();

    try {
      final contentHtml = body;
      final existingId = _persistedId;

      // Slug is generated once and preserved across edits, matching the web
      // form's `editingArticle?.slug || generateSlug(title)`.
      final slug = _existing?.slug.isNotEmpty == true
          ? _existing!.slug
          : generateSlug(title.trim(), randomSuffix: _randomSuffix());

      if (existingId == null) {
        _persistedId = await _service.create(
          title: title.trim(),
          slug: slug,
          contentHtml: contentHtml,
          brief: brief.trim(),
          category: category,
          tags: parsedTags,
          imageUrl: imageUrl.trim().isEmpty ? null : imageUrl.trim(),
          authorName: authorName,
          authorImageUrl: authorImageUrl,
          readTime: readTime,
          userId: userId,
          userType: userType,
          isAdmin: isAdmin,
          submitForReview: submitForReview,
        );
      } else {
        await _service.update(
          id: existingId,
          title: title.trim(),
          slug: slug,
          contentHtml: contentHtml,
          brief: brief.trim(),
          category: category,
          tags: parsedTags,
          imageUrl: imageUrl.trim().isEmpty ? null : imageUrl.trim(),
          authorName: authorName,
          authorImageUrl: authorImageUrl,
          readTime: readTime,
          userId: userId,
          userType: userType,
          isAdmin: isAdmin,
          submitForReview: submitForReview,
        );
      }

      return null;
    } catch (e) {
      debugPrint('ArticleEditorProvider._persist failed: $e');
      return submitForReview
          ? 'Could not submit the article. Please try again.'
          : 'Could not save the draft. Please try again.';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Six lowercase alphanumerics, matching the web form's
  /// `Math.random().toString(36).substring(2, 8)`.
  String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
