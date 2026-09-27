import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Shows a Calibre comment (`comments.text`, which is HTML) as formatted
/// text, without any third-party HTML renderer.
///
/// Supports what Calibre descriptions actually contain: paragraphs/divs,
/// line breaks, headings, bold/italic/underline/strike, lists and
/// blockquotes. Unknown tags are rendered as their text content. Plain text
/// (no tags) is shown as-is.
class HtmlDescription extends StatelessWidget {
  const HtmlDescription(this.html, {super.key, this.style});

  final String html;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final builder = _SpanBuilder(base);
    builder.walk(html_parser.parseFragment(html).nodes, base);
    return SelectableText.rich(TextSpan(children: builder.finish()));
  }
}

class _SpanBuilder {
  _SpanBuilder(this.base);

  final TextStyle base;
  final List<InlineSpan> _spans = [];

  /// Number of newlines at the end of what has been written so far
  /// (used to avoid piling up blank lines between blocks).
  int _trailingNewlines = 2; // start of text counts as "after a block"

  static const _blockTags = {
    'p', 'div', 'section', 'article', 'header', 'footer', 'blockquote',
    'pre', 'ul', 'ol', 'table', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  List<InlineSpan> finish() {
    // Drop trailing blank lines.
    while (_spans.isNotEmpty) {
      final last = _spans.last;
      if (last is TextSpan && (last.text ?? '').trim().isEmpty) {
        _spans.removeLast();
      } else {
        break;
      }
    }
    return _spans;
  }

  void _text(String text, TextStyle style) {
    if (text.isEmpty) return;
    if (_trailingNewlines > 0) text = text.trimLeft();
    if (text.isEmpty) return;
    _spans.add(TextSpan(text: text, style: style));
    _trailingNewlines = 0;
  }

  void _newlines(int count) {
    if (_trailingNewlines >= count) return;
    _spans.add(TextSpan(text: '\n' * (count - _trailingNewlines)));
    _trailingNewlines = count;
  }

  void walk(List<dom.Node> nodes, TextStyle style, {bool pre = false}) {
    for (final node in nodes) {
      if (node is dom.Text) {
        final text =
            pre ? node.text : node.text.replaceAll(RegExp(r'\s+'), ' ');
        _text(text, style);
      } else if (node is dom.Element) {
        _element(node, style, pre: pre);
      }
    }
  }

  void _element(dom.Element el, TextStyle style, {required bool pre}) {
    final tag = el.localName ?? '';
    switch (tag) {
      case 'br':
        _spans.add(const TextSpan(text: '\n'));
        _trailingNewlines = _trailingNewlines + 1;
        return;
      case 'script':
      case 'style':
        return;
      case 'li':
        _newlines(1);
        final parent = el.parent?.localName;
        final marker = parent == 'ol'
            ? '${el.parent!.children.indexOf(el) + 1}. '
            : '• ';
        _spans.add(TextSpan(text: marker, style: style));
        _trailingNewlines = 0;
        walk(el.nodes, style, pre: pre);
        _newlines(1);
        return;
    }

    final childStyle = _styleFor(tag, style);
    final isBlock = _blockTags.contains(tag);
    if (isBlock) _newlines(tag == 'ul' || tag == 'ol' || tag == 'tr' ? 1 : 2);
    walk(el.nodes, childStyle, pre: pre || tag == 'pre');
    if (isBlock) _newlines(tag == 'tr' ? 1 : 2);
  }

  TextStyle _styleFor(String tag, TextStyle style) {
    final size = base.fontSize ?? 14;
    switch (tag) {
      case 'b':
      case 'strong':
        return style.copyWith(fontWeight: FontWeight.bold);
      case 'i':
      case 'em':
      case 'cite':
        return style.copyWith(fontStyle: FontStyle.italic);
      case 'u':
      case 'ins':
        return style.copyWith(decoration: TextDecoration.underline);
      case 's':
      case 'strike':
      case 'del':
        return style.copyWith(decoration: TextDecoration.lineThrough);
      case 'blockquote':
        return style.copyWith(fontStyle: FontStyle.italic);
      case 'pre':
      case 'code':
        return style.copyWith(fontFamily: 'monospace');
      case 'h1':
        return style.copyWith(fontSize: size * 1.6, fontWeight: FontWeight.bold);
      case 'h2':
        return style.copyWith(fontSize: size * 1.4, fontWeight: FontWeight.bold);
      case 'h3':
        return style.copyWith(fontSize: size * 1.2, fontWeight: FontWeight.bold);
      case 'h4':
      case 'h5':
      case 'h6':
        return style.copyWith(fontWeight: FontWeight.bold);
      default:
        return style;
    }
  }
}
