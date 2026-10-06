import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../utils/html_text.dart';

/// Shows a Calibre comment (`comments.text`, which is HTML) as formatted
/// text, rendered by `HtmlWidget` from flutter_widget_from_html_core (the
/// same renderer the EPUB reader uses).
///
/// Plain text descriptions (no tags, e.g. written by older app versions)
/// are converted to paragraphs first, so their line breaks are kept.
class HtmlDescription extends StatelessWidget {
  const HtmlDescription(this.html, {super.key, this.style});

  final String html;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final source = html.trim();
    if (source.isEmpty) return const SizedBox.shrink();

    return SelectionArea(
      child: HtmlWidget(
        HtmlText.looksLikeHtml(source) ? source : HtmlText.toHtml(source),
        textStyle: style,
        // Links in descriptions are not opened.
        onTapUrl: (_) => true,
      ),
    );
  }
}
