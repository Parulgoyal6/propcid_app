/// Bridges the Quill rich-text editor and the HTML `cms_posts.content`/
/// `content_html` columns, so the mobile article editor produces the same
/// kind of HTML the web's Tiptap editor does (headings, bold/italic/
/// underline, lists, blockquote, alignment, links, images).
library;

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

/// The stored article HTML → a Quill [Document] the editor can load.
Document articleHtmlToDocument(String? html) {
  if (html == null || html.trim().isEmpty) return Document();
  final delta = HtmlToDelta().convert(html);
  return Document.fromDelta(delta);
}

/// The editor's current [Document] → HTML for `content`/`content_html`.
///
/// `inlineStylesFlag` is required: without it, block attributes such as
/// alignment are emitted as CSS classes (e.g. `class="ql-align-center"`)
/// instead of `style="text-align:center"`. [HtmlToDelta] (used by
/// [articleHtmlToDocument]) only understands the inline-style form, so a
/// class-based export would silently lose alignment the next time the
/// article is reopened.
String articleDocumentToHtml(Document document) {
  final ops = document.toDelta().toJson().cast<Map<String, dynamic>>();
  return QuillDeltaToHtmlConverter(
    ops,
    ConverterOptions(
      converterOptions: OpConverterOptions(inlineStylesFlag: true),
    ),
  ).convert();
}
