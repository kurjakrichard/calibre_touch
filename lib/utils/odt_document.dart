import 'dart:typed_data';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../metadata/readers/office_files.dart';
import 'utils.dart';

/// Opens OpenDocument text (.odt, LibreOffice / Google Docs) for the
/// built-in reader: headings (`text:h`, outline levels), paragraphs with
/// bold/italic/underline from the automatic and named styles, nested
/// lists, tables, images and footnotes/endnotes (shown at the end of the
/// chapter). The document's own table of contents is left out.
///
/// Pure Dart: call [OdtDocument.parse] through `compute`.
class OdtDocument {
  OdtDocument._();

  static const extensions = {'odt'};

  static Future<EpubDocument> parse(Uint8List bytes) async {
    final zip = ZipFiles.open(bytes);
    final content = zip.xml('content.xml');
    final text = content?.rootElement.kid('body')?.kid('text');
    if (content == null || text == null) {
      throw const FormatException('Not an OpenDocument text');
    }
    final converter = _OdtConverter(zip)
      ..readStyles(zip.xml('styles.xml')?.rootElement)
      ..readStyles(content.rootElement);
    converter.convertChildren(text);
    return DocumentBuilder.build(converter.blocks, files: converter.files);
  }
}

class _OdtStyle {
  _OdtStyle(this.parent);
  final String? parent;
  bool? bold;
  bool? italic;
  bool? underline;
  bool? center;
  int outlineLevel = 0;
  bool title = false;
}

class _OdtConverter {
  _OdtConverter(this.zip);

  final ZipFiles zip;
  final blocks = <DocBlock>[];
  final files = <String, Uint8List>{};
  final _styles = <String, _OdtStyle>{};
  var _blanks = 0;

  // Notes referenced since the last block was added.
  final _pendingNotes = <String>[];
  var _noteNumber = 0;

  List<String> _takeNotes() {
    final notes = List<String>.of(_pendingNotes);
    _pendingNotes.clear();
    return notes;
  }

  /// Reads `style:style` elements from office:styles and
  /// office:automatic-styles of [root] (styles.xml or content.xml).
  void readStyles(XmlElement? root) {
    if (root == null) return;
    for (final group in [root.kid('styles'), root.kid('automatic-styles')]) {
      for (final s in group?.kids('style') ?? const <XmlElement>[]) {
        final name = s.attr('name');
        if (name == null) continue;
        final style = _OdtStyle(s.attr('parent-style-name'));
        final textProps = s.kid('text-properties');
        if (textProps != null) {
          final weight = textProps.attr('font-weight');
          if (weight != null) style.bold = weight == 'bold' || weight == '700';
          final fontStyle = textProps.attr('font-style');
          if (fontStyle != null) style.italic = fontStyle == 'italic';
          final under = textProps.attr('text-underline-style');
          if (under != null) style.underline = under != 'none';
        }
        final align = s.kid('paragraph-properties')?.attr('text-align');
        if (align != null) style.center = align == 'center';
        style.outlineLevel =
            int.tryParse(s.attr('default-outline-level') ?? '') ?? 0;
        final display = (s.attr('display-name') ?? name).toLowerCase();
        style.title = display == 'title' || name == 'Title';
        _styles[name] = style;
      }
    }
  }

  /// Looks up [property] along the parent-style chain.
  T? _prop<T>(String? styleName, T? Function(_OdtStyle s) property) {
    final seen = <String>{};
    var name = styleName;
    while (name != null && seen.add(name)) {
      final style = _styles[name];
      if (style == null) return null;
      final value = property(style);
      if (value != null) return value;
      name = style.parent;
    }
    return null;
  }

  void convertChildren(XmlElement parent) {
    for (final e in parent.childElements) {
      switch (e.local) {
        case 'p':
        case 'h':
          _paragraph(e);
        case 'list':
          _list(e);
        case 'table':
          _table(e);
        case 'section':
          convertChildren(e);
        default:
          break; // table-of-content, sequence-decls, soft-page-break ...
      }
    }
  }

  void _paragraph(XmlElement para) {
    final styleName = para.attr('style-name');
    final html = StringBuffer();
    final text = StringBuffer();
    _inline(para, html, text);
    final inner = html.toString().trim();
    final plain = text.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.isEmpty && !inner.contains('<img')) {
      _blanks++;
      return;
    }

    var heading = 0;
    if (para.local == 'h') {
      heading = int.tryParse(para.attr('outline-level') ?? '') ?? 1;
    } else {
      heading = _prop(styleName, (s) => s.outlineLevel > 0 ? s.outlineLevel : null) ?? 0;
    }
    final title = _prop(styleName, (s) => s.title ? true : null) ?? false;
    final center = _prop(styleName, (s) => s.center) ?? false;
    final align = center ? ' style="text-align:center"' : '';

    final notes = _takeNotes();
    if (title) {
      blocks.add(DocBlock('<h1$align>$inner</h1>',
          text: plain, blanksBefore: _blanks, notes: notes));
    } else if (heading > 0) {
      final tag = 'h${(heading + 1).clamp(2, 6)}';
      blocks.add(DocBlock('<$tag>$inner</$tag>',
          text: plain, heading: heading, blanksBefore: _blanks, notes: notes));
    } else {
      blocks.add(DocBlock('<p$align>$inner</p>',
          text: plain, paragraph: true, blanksBefore: _blanks, notes: notes));
    }
    _blanks = 0;
  }

  void _list(XmlElement list) {
    final items = NestedList();
    void collect(XmlElement l, int level) {
      for (final item in l.childElements) {
        if (item.local != 'list-item' && item.local != 'list-header') continue;
        for (final child in item.childElements) {
          if (child.local == 'list') {
            collect(child, level + 1);
          } else if (child.local == 'p' || child.local == 'h') {
            final html = StringBuffer();
            _inline(child, html, StringBuffer());
            final inner = html.toString().trim();
            if (inner.isNotEmpty) items.add(level, 'ul', inner);
          }
        }
      }
    }

    collect(list, 0);
    if (items.isEmpty) return;
    blocks.add(DocBlock(items.finish(),
        blanksBefore: _blanks, notes: _takeNotes()));
    _blanks = 0;
  }

  void _table(XmlElement table) {
    final rows = StringBuffer();
    final allRows = [
      ...table.kids('table-header-rows').expand((h) => h.kids('table-row')),
      ...table.kids('table-row'),
      ...table.kids('table-rows').expand((h) => h.kids('table-row')),
    ];
    for (final row in allRows) {
      rows.write('<tr>');
      for (final cell in row.kids('table-cell')) {
        final parts = <String>[];
        for (final para in cell.deep('p')) {
          final html = StringBuffer();
          _inline(para, html, StringBuffer());
          final inner = html.toString().trim();
          if (inner.isNotEmpty) parts.add(inner);
        }
        rows.write('<td>${parts.join('<br>')}</td>');
      }
      rows.write('</tr>');
    }
    blocks.add(DocBlock('<table border="1">$rows</table>',
        blanksBefore: _blanks, notes: _takeNotes()));
    _blanks = 0;
  }

  /// Inline content of a paragraph / span / link.
  void _inline(XmlElement parent, StringBuffer html, StringBuffer text) {
    for (final node in parent.children) {
      if (node is XmlText || node is XmlCDATA) {
        // ODF collapses white space like HTML.
        final value = node.value ?? '';
        final t = value.replaceAll(RegExp(r'\s+'), ' ');
        html.write(DocumentBuilder.escape(t));
        text.write(t);
        continue;
      }
      if (node is! XmlElement) continue;
      switch (node.local) {
        case 's':
          final count = int.tryParse(node.attr('c') ?? '') ?? 1;
          html.write(' ' * count.clamp(1, 20));
          text.write(' ');
        case 'tab':
          html.write(' ');
          text.write(' ');
        case 'line-break':
          html.write('<br>');
          text.write(' ');
        case 'span':
          final styleName = node.attr('style-name');
          final inner = StringBuffer();
          _inline(node, inner, text);
          var out = inner.toString();
          if (out.isEmpty) break;
          if (_prop(styleName, (s) => s.underline) ?? false) out = '<u>$out</u>';
          if (_prop(styleName, (s) => s.italic) ?? false) out = '<i>$out</i>';
          if (_prop(styleName, (s) => s.bold) ?? false) out = '<b>$out</b>';
          html.write(out);
        case 'a':
        case 'meta':
        case 'ruby':
        case 'ruby-base':
          _inline(node, html, text);
        case 'note':
          // Footnote / endnote: citation + body.
          final body = node.kid('note-body');
          if (body == null) break;
          final parts = <String>[];
          for (final para in body.deep('p')) {
            final inner = StringBuffer();
            _inline(para, inner, StringBuffer());
            final h = inner.toString().trim();
            if (h.isNotEmpty) parts.add(h);
          }
          final marker = '[${++_noteNumber}]';
          html.write('<sup>$marker</sup>');
          _pendingNotes.add(DocumentBuilder.noteHtml(marker, parts.join('<br>')));
        case 'frame':
          for (final image in node.kids('image')) {
            final img = _image(image.attr('href'));
            if (img != null) {
              html.write(img);
              break;
            }
          }
        default:
          break; // note, annotation, bookmark, soft-page-break, ...
      }
    }
  }

  String? _image(String? href) {
    if (href == null || href.contains('://')) return null;
    final path = p.posix.normalize(href.replaceFirst(RegExp(r'^\./'), ''));
    if (!files.containsKey(path)) {
      final bytes = zip.data(path);
      if (bytes == null || !DocumentBuilder.isDisplayableImage(bytes)) {
        return null;
      }
      files[path] = bytes;
    }
    return '<img src="${DocumentBuilder.escape(path)}">';
  }
}
