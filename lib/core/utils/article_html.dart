/// Small text utilities shared by the Article Editor: a rough word counter
/// (for the read-time default) and the slug generator that mirrors the web
/// form's `generateSlug`. HTML itself is now produced and consumed directly
/// by the Quill rich-text editor — see article_content_converter.dart.
library;

/// Rough word count used for the read-time estimate.
int wordCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// Read time in minutes at ~200 wpm, floored at 1.
///
/// The column defaults to 5 and the web form lets an author override it; the
/// mobile form derives a sensible starting value instead of shipping a raw
/// number input.
int estimateReadTime(String text) {
  final words = wordCount(text);
  if (words == 0) return 1;
  final minutes = (words / 200).ceil();
  return minutes < 1 ? 1 : minutes;
}

/// `my-article-title-a1b2c3` — mirrors `generateSlug` in ArticleWriteForm.tsx:
/// a slugified title plus a six-character suffix.
String generateSlug(String title, {required String randomSuffix}) {
  final base = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'(^-+)|(-+$)'), '');

  return base.isEmpty ? randomSuffix : '$base-$randomSuffix';
}
