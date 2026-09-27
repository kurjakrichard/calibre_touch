import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Converts between Calibre's HTML comments (`comments.text`) and the plain
/// text shown in the app's edit field.
///
/// Calibre always stores a book's description as HTML (usually
/// `<div><p>...</p></div>`), so everything written to `comments.text` must
/// be HTML too, otherwise Calibre shows it as one run-on paragraph.
class HtmlText {
  const HtmlText._();

  static final RegExp _tagPattern = RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>');

  /// True if [text] already contains HTML tags.
  static bool looksLikeHtml(String text) => _tagPattern.hasMatch(text);

  /// Plain text (paragraphs separated by blank lines, line breaks by `\n`)
  /// -> Calibre-style HTML. Text that is already HTML is returned unchanged.
  static String toHtml(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || looksLikeHtml(trimmed)) return trimmed;

    final paragraphs = trimmed
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => '<p>${_escape(p).replaceAll('\n', '<br>')}</p>');
    return '<div>\n${paragraphs.join('\n')}\n</div>';
  }

  /// HTML -> readable plain text for editing (block elements become blank
  /// lines, `<br>` becomes a newline, entities are decoded).
  static String toPlainText(String html) {
    if (html.trim().isEmpty) return '';
    if (!looksLikeHtml(html)) return html.trim();

    final fragment = html_parser.parseFragment(html);
    final buffer = StringBuffer();
    _walk(fragment.nodes, buffer);
    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static const _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre',
    'ul', 'ol', 'table', 'tr', 'section', 'article', 'header', 'footer',
  };

  static void _walk(List<dom.Node> nodes, StringBuffer out) {
    for (final node in nodes) {
      if (node is dom.Text) {
        out.write(node.text.replaceAll(RegExp(r'\s+'), ' '));
      } else if (node is dom.Element) {
        final tag = node.localName ?? '';
        if (tag == 'br') {
          out.write('\n');
        } else if (tag == 'li') {
          out.write('\n• ');
          _walk(node.nodes, out);
        } else if (_blockTags.contains(tag)) {
          out.write('\n\n');
          _walk(node.nodes, out);
          out.write('\n\n');
        } else {
          _walk(node.nodes, out);
        }
      }
    }
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
