// Locks the HTML <-> Quill Document round trip the rich-text Article Editor
// relies on: `cms_posts.content_html` must survive being loaded into the
// editor and saved back out with its formatting intact.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/core/utils/article_content_converter.dart';

void main() {
  test('empty/null html loads as an empty document', () {
    expect(articleHtmlToDocument(null).toPlainText(), '\n');
    expect(articleHtmlToDocument('').toPlainText(), '\n');
  });

  test('paragraph and formatting round-trips', () {
    const html = '<p>Hello <strong>world</strong></p>';
    final document = articleHtmlToDocument(html);
    expect(document.toPlainText().trim(), 'Hello world');

    final out = articleDocumentToHtml(document);
    expect(out.contains('<strong>world</strong>'), isTrue);
  });

  test('heading, list and blockquote survive the round trip', () {
    const html = '<h1>Title</h1>'
        '<ul><li>one</li><li>two</li></ul>'
        '<blockquote>quoted</blockquote>';
    final out = articleDocumentToHtml(articleHtmlToDocument(html));
    expect(out.contains('<h1>Title</h1>'), isTrue);
    expect(out.contains('<ul>'), isTrue);
    expect(out.contains('<li>one</li>'), isTrue);
    expect(out.contains('<blockquote>'), isTrue);
  });

  test('center/right alignment survives the save/reopen round trip', () {
    const html = '<p>left line</p>'
        '<p style="text-align: center">center line</p>'
        '<p style="text-align: right">right line</p>';

    // Simulates reopening a saved article: HTML -> Document -> HTML again.
    final reopened = articleDocumentToHtml(articleHtmlToDocument(html));

    expect(reopened.contains('text-align: center') ||
        reopened.contains('text-align:center'), isTrue,
        reason: 'center alignment must round-trip as HTML the editor '
            'understands on reopen:\n$reopened');
    expect(reopened.contains('text-align: right') ||
        reopened.contains('text-align:right'), isTrue,
        reason: 'right alignment must round-trip as HTML the editor '
            'understands on reopen:\n$reopened');

    // And it must actually still carry the align attribute once reloaded
    // into a Document a second time, not just appear as text in the HTML.
    final doc = articleHtmlToDocument(reopened);
    final aligns = doc
        .toDelta()
        .toList()
        .map((op) => op.attributes?['align'])
        .where((a) => a != null)
        .toList();
    expect(aligns, containsAll(['center', 'right']));
  });
}
