import 'dart:typed_data';
import 'package:xml/xml.dart';
import '../metadata/readers/fb2_metadata_reader.dart';
import '../metadata/readers/office_files.dart';
import 'utils.dart';

/// Opens FictionBook (.fb2 / .fbz) books for the built-in reader:
/// sections (nested) become chapters and the contents, with titles,
/// epigraphs, poems, citations, subtitles, tables, pictures (`<binary>`)
/// and footnotes (the "notes" body, shown at the end of the chapter that
/// refers to them).
///
/// Pure Dart: call [Fb2Document.parse] through `compute`.
class Fb2Document {
  Fb2Document._();

  static const extensions = {'fb2', 'fbz'};

  static Future<EpubDocument> parse(Uint8List bytes) async {
    final fb2 = Fb2File.parse(bytes);
    final converter = _Fb2Converter(fb2);
    final bodies = fb2.root.kids('body').toList();
    final main = bodies.firstWhere(
        (b) => !_isNotesBody(b),
        orElse: () => throw const FormatException('The book has no body'));
    for (final body in bodies.where(_isNotesBody)) {
      converter.readNotes(body);
    }
    converter.body(main);
    return DocumentBuilder.build(converter.blocks, files: converter.files);
  }

  static bool _isNotesBody(XmlElement body) {
    final name = (body.attr('name') ?? '').toLowerCase();
    return name == 'notes' || name == 'comments' || name == 'footnotes';
  }
}

class _Fb2Converter {
  _Fb2Converter(this.fb2) : _binaries = fb2.binaries;

  final Fb2File fb2;
  final Map<String, Uint8List> _binaries;
  final blocks = <DocBlock>[];
  final files = <String, Uint8List>{};

  // binary id -> path in [files] ("images/3"), so odd ids are no problem.
  final _imagePaths = <String, String>{};

  // Note id -> note text (HTML), from the notes body.
  final _notes = <String, String>{};
  final _pendingNotes = <String>[];
  var _blanks = 0;

  List<String> _takeNotes() {
    final notes = List<String>.of(_pendingNotes);
    _pendingNotes.clear();
    return notes;
  }

  void _add(String html, {String text = '', int heading = 0}) {
    blocks.add(DocBlock(html,
        text: text,
        heading: heading,
        paragraph: heading == 0 && text.isNotEmpty,
        blanksBefore: _blanks,
        notes: _takeNotes()));
    _blanks = 0;
  }

  // ---- notes ----

  void readNotes(XmlElement body) {
    for (final section in body.deep('section')) {
      final id = section.attr('id');
      if (id == null) continue;
      final parts = <String>[];
      for (final child in section.childElements) {
        if (child.local == 'title' || child.local == 'section') continue;
        final html = _blockHtml(child);
        if (html.isNotEmpty) parts.add(html);
      }
      _notes[id] = parts.join();
    }
    // Links between notes don't belong to the first chapter.
    _pendingNotes.clear();
  }

  // ---- body ----

  void body(XmlElement body) {
    for (final child in body.childElements) {
      switch (child.local) {
        case 'title':
          // The book's title page.
          final lines = _titleLines(child);
          if (lines.isNotEmpty) {
            _add('<h1 style="text-align:center">${lines.join('<br>')}</h1>');
          }
        case 'epigraph':
          _add(_epigraph(child));
        case 'image':
          final img = _image(child);
          if (img != null) _add('<p style="text-align:center">$img</p>');
        case 'section':
          _section(child, 1);
        default:
          break;
      }
    }
  }

  void _section(XmlElement section, int depth) {
    for (final child in section.childElements) {
      switch (child.local) {
        case 'title':
          final lines = _titleLines(child);
          if (lines.isEmpty) break;
          final tag = 'h${(depth + 1).clamp(2, 6)}';
          final text = OfficeText.clean(child.innerText);
          _add('<$tag>${lines.join('<br>')}</$tag>',
              text: text, heading: depth);
        case 'section':
          _section(child, depth + 1);
        case 'empty-line':
          _blanks++;
        default:
          final html = _blockHtml(child);
          if (html.isNotEmpty) {
            final text = child.local == 'p' ? OfficeText.clean(child.innerText) : '';
            _add(html, text: text);
          }
      }
    }
  }

  /// HTML of a block element inside a section.
  String _blockHtml(XmlElement e) {
    switch (e.local) {
      case 'p':
        final inner = _inline(e).trim();
        return inner.isEmpty ? '' : '<p>$inner</p>';
      case 'subtitle':
        final inner = _inline(e).trim();
        return inner.isEmpty
            ? ''
            : '<p style="text-align:center"><b>$inner</b></p>';
      case 'empty-line':
        return '<br>';
      case 'epigraph':
        return _epigraph(e);
      case 'cite':
        return '<blockquote>${_children(e)}</blockquote>';
      case 'poem':
        return _poem(e);
      case 'image':
        final img = _image(e);
        return img == null ? '' : '<p style="text-align:center">$img</p>';
      case 'table':
        return _table(e);
      case 'text-author':
        return '<p style="text-align:right"><i>${_inline(e).trim()}</i></p>';
      case 'title':
        final lines = _titleLines(e);
        return lines.isEmpty ? '' : '<p><b>${lines.join('<br>')}</b></p>';
      default:
        return '';
    }
  }

  String _children(XmlElement e) =>
      e.childElements.map(_blockHtml).where((h) => h.isNotEmpty).join();

  String _epigraph(XmlElement e) => '<blockquote><i>${_children(e)}</i></blockquote>';

  String _poem(XmlElement poem) {
    final out = StringBuffer('<blockquote>');
    for (final child in poem.childElements) {
      switch (child.local) {
        case 'title':
          out.write('<p><b>${_titleLines(child).join('<br>')}</b></p>');
        case 'epigraph':
          out.write(_epigraph(child));
        case 'stanza':
          final lines = <String>[];
          for (final s in child.childElements) {
            if (s.local == 'v') lines.add(_inline(s).trim());
            if (s.local == 'title' || s.local == 'subtitle') {
              lines.add('<b>${_inline(s).trim()}</b>');
            }
          }
          if (lines.isNotEmpty) out.write('<p>${lines.join('<br>')}</p>');
        case 'text-author':
        case 'date':
          out.write('<p style="text-align:right"><i>'
              '${_inline(child).trim()}</i></p>');
        default:
          break;
      }
    }
    out.write('</blockquote>');
    return out.toString();
  }

  String _table(XmlElement table) {
    final rows = StringBuffer();
    for (final tr in table.kids('tr')) {
      rows.write('<tr>');
      for (final cell in tr.childElements) {
        if (cell.local != 'td' && cell.local != 'th') continue;
        rows.write('<${cell.local}>${_inline(cell).trim()}</${cell.local}>');
      }
      rows.write('</tr>');
    }
    return '<table border="1">$rows</table>';
  }

  /// Lines of a `<title>` (its `<p>`s) as inline HTML.
  List<String> _titleLines(XmlElement title) {
    final lines = <String>[];
    for (final child in title.childElements) {
      if (child.local == 'p') {
        final inner = _inline(child).trim();
        if (inner.isNotEmpty) lines.add(inner);
      }
    }
    return lines;
  }

  // ---- inline ----

  String _inline(XmlElement e) {
    final out = StringBuffer();
    for (final node in e.children) {
      if (node is XmlText || node is XmlCDATA) {
        out.write(DocumentBuilder.escape(
            (node.value ?? '').replaceAll(RegExp(r'\s+'), ' ')));
        continue;
      }
      if (node is! XmlElement) continue;
      switch (node.local) {
        case 'strong':
          out.write('<b>${_inline(node)}</b>');
        case 'emphasis':
          out.write('<i>${_inline(node)}</i>');
        case 'strikethrough':
          out.write('<s>${_inline(node)}</s>');
        case 'sub':
          out.write('<sub>${_inline(node)}</sub>');
        case 'sup':
          out.write('<sup>${_inline(node)}</sup>');
        case 'code':
          out.write('<code>${_inline(node)}</code>');
        case 'image':
          out.write(_image(node) ?? '');
        case 'a':
          final target = Fb2File.linkTarget(node);
          final note = target == null ? null : _notes[target];
          final label = OfficeText.clean(node.innerText);
          if (note != null) {
            // Footnote reference: [label] here, the text at chapter end.
            final marker = '[${label.replaceAll(RegExp(r'[\[\]{}]'), '')}]';
            out.write('<sup>$marker</sup>');
            _pendingNotes.add(DocumentBuilder.noteHtml(marker, note));
          } else {
            out.write(_inline(node));
          }
        default:
          out.write(_inline(node)); // style, ...
      }
    }
    return out.toString();
  }

  /// `<img>` for an FB2 `<image l:href="#id">`, or null.
  String? _image(XmlElement image) {
    final id = Fb2File.linkTarget(image);
    if (id == null) return null;
    var path = _imagePaths[id];
    if (path == null) {
      final bytes = _binaries[id];
      if (bytes == null || !DocumentBuilder.isDisplayableImage(bytes)) {
        return null;
      }
      path = 'images/${_imagePaths.length + 1}';
      _imagePaths[id] = path;
      files[path] = bytes;
    }
    return '<img src="$path">';
  }
}
