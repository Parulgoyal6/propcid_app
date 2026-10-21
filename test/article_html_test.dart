// Locks the small text utilities the Article Editor shares with the React
// portal: the read-time estimate and the slug generator. HTML production is
// now handled by the Quill rich-text editor (article_content_converter.dart),
// not by this file.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/core/utils/article_html.dart';

void main() {
  test('slug mirrors the web generator', () {
    expect(generateSlug('My Great Article!', randomSuffix: 'a1b2c3'),
        'my-great-article-a1b2c3');
    expect(generateSlug('   ', randomSuffix: 'a1b2c3'), 'a1b2c3');
  });

  test('read time', () {
    expect(estimateReadTime(''), 1);
    expect(estimateReadTime(List.filled(400, 'word').join(' ')), 2);
  });
}
