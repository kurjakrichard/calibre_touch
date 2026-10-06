import 'dart:typed_data';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'utils.dart';
import '../metadata/readers/office_files.dart';

/// Opens Word (.docx / .docm) documents for the built-in reader:
/// paragraphs with bold/italic/underline, headings (from the styles, also
/// in localised Word - "Címsor 1" is still "heading 1" inside), nested
/// lists, tables, images (PNG/JPEG/GIF/BMP; EMF/WMF are skipped) and
/// footnotes/endnotes (numbered [1], [2], ... and shown at the end of the
/// chapter). Word's own table of contents is left out - the reader has its
/// own.
///
/// Pure Dart: call [DocxDocument.parse] through `compute`.
class DocxDocument {
  DocxDocument._();

  static const extensions = {'docx', 'docm'};

  static Future<EpubDocument> parse(Uint8List bytes) async {
    final zip = ZipFiles.open(bytes);
    final docPath = OfficeRels.mainDocumentPath(zip);
    final document = zip.xml(docPath);
    final body = document?.rootElement.kid('body');
    if (body == null) throw const FormatException('Not a Word document');

    final converter = _DocxConverter(zip, docPath);
    converter.convertChildren(body);
    converter.flushList();
    return DocumentBuilder.build(converter.blocks, files: converter.files);
  }
}

/// What a paragraph / character style means for us.
class _DocxStyle {
  _DocxStyle({this.basedOn, this.heading = 0, this.title = false,
      this.toc = false, this.bold, this.italic, this.center = false,
      this.numId});
  final String? basedOn;
  String? numId; // list style ("List Bullet" has its numbering here)
  int heading;
  bool title;
  bool toc;
  bool? bold;
  bool? italic;
  bool center;
}

class _DocxConverter {
  _DocxConverter(this.zip, String docPath)
      : rels = OfficeRels.relationships(zip, docPath) {
    final dir = p.posix.dirname(docPath);
    _readStyles(dir);
    _readNumbering(dir);
    _readNotes('$dir/footnotes.xml', 'footnote', _footnotes);
    _readNotes('$dir/endnotes.xml', 'endnote', _endnotes);
  }

  final ZipFiles zip;
  final Map<String, String> rels;
  final blocks = <DocBlock>[];
  final files = <String, Uint8List>{};

  final _styles = <String, _DocxStyle>{};
  // numId -> ilvl -> numFmt ("bullet", "decimal", ...)
  final _numFormats = <String, Map<String, String>>{};

  var _blanks = 0;

  // The list being collected, and the notes referenced in it.
  NestedList? _list;
  final _listNotes = <String>[];

  // Footnotes / endnotes by id, and the notes referenced since the last
  // block was added.
  final _footnotes = <String, XmlElement>{};
  final _endnotes = <String, XmlElement>{};
  final _pendingNotes = <String>[];
  var _noteNumber = 0;

  void _readNotes(String path, String element, Map<String, XmlElement> into) {
    for (final note in zip.xml(path)?.rootElement.kids(element) ??
        const <XmlElement>[]) {
      final id = note.attr('id');
      if (id != null) into[id] = note;
    }
  }

  List<String> _takeNotes() {
    final notes = List<String>.of(_pendingNotes);
    _pendingNotes.clear();
    return notes;
  }

  // ---- styles ----

  void _readStyles(String dir) {
    final doc = zip.xml('$dir/styles.xml');
    for (final s in doc?.rootElement.kids('style') ?? const <XmlElement>[]) {
      final id = s.attr('styleId');
      if (id == null) continue;
      final name = (s.kid('name')?.attr('val') ?? '').toLowerCase();
      final style = _DocxStyle(basedOn: s.kid('basedOn')?.attr('val'));
      final heading = RegExp(r'^heading (\d)$').firstMatch(name);
      if (heading != null) style.heading = int.parse(heading.group(1)!);
      final outline = s.kid('pPr')?.kid('outlineLvl')?.attr('val');
      if (style.heading == 0 && outline != null) {
        final level = int.tryParse(outline);
        if (level != null && level < 6) style.heading = level + 1;
      }
      style.title = name == 'title';
      style.toc = name.startsWith('toc ') || name == 'toc heading';
      final rPr = s.kid('rPr');
      if (rPr != null) {
        style.bold = _onOff(rPr.kid('b'));
        style.italic = _onOff(rPr.kid('i'));
      }
      style.center = s.kid('pPr')?.kid('jc')?.attr('val') == 'center';
      style.numId = s.kid('pPr')?.kid('numPr')?.kid('numId')?.attr('val');
      _styles[id] = style;
    }
  }

  /// A style with its basedOn chain resolved.
  _DocxStyle? _style(String? id) {
    final style = id == null ? null : _styles[id];
    if (style == null) return null;
    final seen = <String>{id!};
    var parentId = style.basedOn;
    final resolved = _DocxStyle(
      heading: style.heading,
      title: style.title,
      toc: style.toc,
      bold: style.bold,
      italic: style.italic,
      center: style.center,
      numId: style.numId,
    );
    while (parentId != null && seen.add(parentId)) {
      final parent = _styles[parentId];
      if (parent == null) break;
      if (resolved.heading == 0) resolved.heading = parent.heading;
      resolved.bold ??= parent.bold;
      resolved.italic ??= parent.italic;
      resolved.numId ??= parent.numId;
      parentId = parent.basedOn;
    }
    return resolved;
  }

  void _readNumbering(String dir) {
    final doc = zip.xml('$dir/numbering.xml');
    if (doc == null) return;
    final abstract = <String, Map<String, String>>{};
    for (final a in doc.rootElement.kids('abstractNum')) {
      final id = a.attr('abstractNumId');
      if (id == null) continue;
      abstract[id] = {
        for (final lvl in a.kids('lvl'))
          lvl.attr('ilvl') ?? '0': lvl.kid('numFmt')?.attr('val') ?? 'bullet',
      };
    }
    for (final n in doc.rootElement.kids('num')) {
      final id = n.attr('numId');
      final abstractId = n.kid('abstractNumId')?.attr('val');
      if (id != null && abstractId != null && abstract[abstractId] != null) {
        _numFormats[id] = abstract[abstractId]!;
      }
    }
  }

  /// `<w:b/>` = on, `<w:b w:val="0"/>` / "false" = off, missing = null.
  static bool? _onOff(XmlElement? e) {
    if (e == null) return null;
    final v = e.attr('val');
    return v == null || !(v == '0' || v == 'false' || v == 'off');
  }

  // ---- body ----

  void convertChildren(XmlElement parent) {
    for (final e in parent.childElements) {
      switch (e.local) {
        case 'p':
          _paragraph(e);
        case 'tbl':
          flushList();
          _table(e);
        case 'sdt':
          // Content controls; Word's automatic table of contents is one.
          final gallery = e
              .deep('docPartGallery')
              .map((g) => g.attr('val') ?? '')
              .join(' ')
              .toLowerCase();
          final content = e.kid('sdtContent');
          if (content != null && !gallery.contains('table of contents')) {
            convertChildren(content);
          }
        case 'customXml':
        case 'smartTag':
          convertChildren(e);
        default:
          break; // sectPr, bookmarks, ...
      }
    }
  }

  void _paragraph(XmlElement para) {
    final pPr = para.kid('pPr');
    final style = _style(pPr?.kid('pStyle')?.attr('val'));
    if (style?.toc ?? false) return;

    var heading = style?.heading ?? 0;
    final outline = int.tryParse(pPr?.kid('outlineLvl')?.attr('val') ?? '');
    if (outline != null && outline < 6) heading = outline + 1;
    final title = style?.title ?? false;

    final inline = StringBuffer();
    final text = StringBuffer();
    _inline(para, inline, text, style);
    final html = inline.toString().trim();
    final plain = text.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    if (plain.isEmpty && !html.contains('<img')) {
      _blanks++;
      return;
    }

    // Lists
    final numPr = pPr?.kid('numPr');
    final numId = numPr?.kid('numId')?.attr('val') ?? style?.numId;
    if (numId != null && numId != '0' && heading == 0 && !title) {
      final level = numPr?.kid('ilvl')?.attr('val') ?? '0';
      final format = _numFormats[numId]?[level] ?? 'bullet';
      final tag = format == 'bullet' || format == 'none' ? 'ul' : 'ol';
      (_list ??= NestedList()).add(int.tryParse(level) ?? 0, tag, html);
      _listNotes.addAll(_takeNotes());
      _blanks = 0;
      return;
    }
    final notes = _takeNotes();
    flushList();

    final jc = pPr?.kid('jc')?.attr('val') ?? (style?.center ?? false ? 'center' : null);
    final align = jc == 'center'
        ? ' style="text-align:center"'
        : (jc == 'right' || jc == 'end')
            ? ' style="text-align:right"'
            : '';

    if (title) {
      blocks.add(DocBlock('<h1$align>$html</h1>',
          text: plain, blanksBefore: _blanks, notes: notes));
    } else if (heading > 0) {
      final tag = 'h${(heading + 1).clamp(2, 6)}';
      blocks.add(DocBlock('<$tag>$html</$tag>',
          text: plain, heading: heading, blanksBefore: _blanks, notes: notes));
    } else {
      blocks.add(DocBlock('<p$align>$html</p>',
          text: plain, paragraph: true, blanksBefore: _blanks, notes: notes));
    }
    _blanks = 0;
  }

  void flushList() {
    final list = _list;
    _list = null;
    if (list == null || list.isEmpty) return;
    blocks.add(DocBlock(list.finish(),
        blanksBefore: _blanks, notes: List.of(_listNotes)));
    _listNotes.clear();
    _blanks = 0;
  }

  void _table(XmlElement table) {
    final rows = StringBuffer();
    for (final tr in table.kids('tr')) {
      rows.write('<tr>');
      for (final tc in tr.kids('tc')) {
        final cell = <String>[];
        for (final para in tc.deep('p')) {
          final inline = StringBuffer();
          _inline(para, inline, StringBuffer(), null);
          final html = inline.toString().trim();
          if (html.isNotEmpty) cell.add(html);
        }
        rows.write('<td>${cell.join('<br>')}</td>');
      }
      rows.write('</tr>');
    }
    blocks.add(DocBlock('<table border="1">$rows</table>',
        blanksBefore: _blanks, notes: _takeNotes()));
    _blanks = 0;
  }

  // ---- runs ----

  /// Writes the HTML / text of the runs inside [parent] (a paragraph,
  /// hyperlink, ...).
  void _inline(XmlElement parent, StringBuffer html, StringBuffer text,
      _DocxStyle? paragraphStyle) {
    for (final e in parent.childElements) {
      switch (e.local) {
        case 'r':
          _run(e, html, text, paragraphStyle);
        case 'hyperlink':
        case 'ins':
        case 'smartTag':
        case 'customXml':
        case 'fldSimple':
          _inline(e, html, text, paragraphStyle);
        case 'sdt':
          final content = e.kid('sdtContent');
          if (content != null) _inline(content, html, text, paragraphStyle);
        default:
          break; // pPr, del (deleted text), bookmarks, ...
      }
    }
  }

  void _run(XmlElement run, StringBuffer html, StringBuffer text,
      _DocxStyle? paragraphStyle) {
    final rPr = run.kid('rPr');
    final charStyle = _style(rPr?.kid('rStyle')?.attr('val'));
    final bold = _onOff(rPr?.kid('b')) ??
        charStyle?.bold ??
        (paragraphStyle?.heading == 0 ? paragraphStyle?.bold : null) ??
        false;
    final italic = _onOff(rPr?.kid('i')) ??
        charStyle?.italic ??
        (paragraphStyle?.heading == 0 ? paragraphStyle?.italic : null) ??
        false;
    final u = rPr?.kid('u');
    final underline = u != null && (u.attr('val') ?? 'single') != 'none';
    final strike = _onOff(rPr?.kid('strike')) ?? false;
    final vertAlign = rPr?.kid('vertAlign')?.attr('val');

    final content = StringBuffer();
    for (final e in run.childElements) {
      switch (e.local) {
        case 't':
          content.write(DocumentBuilder.escape(e.innerText));
          text.write(e.innerText);
        case 'tab':
          content.write(' ');
          text.write(' ');
        case 'br':
          final type = e.attr('type');
          if (type == null || type == 'textWrapping') {
            content.write('<br>');
            text.write(' ');
          }
        case 'cr':
          content.write('<br>');
          text.write(' ');
        case 'noBreakHyphen':
          content.write('-');
          text.write('-');
        case 'footnoteReference':
        case 'endnoteReference':
          final notes =
              e.local == 'footnoteReference' ? _footnotes : _endnotes;
          final note = notes[e.attr('id') ?? ''];
          if (note != null) {
            final marker = '[${++_noteNumber}]';
            content.write('<sup>$marker</sup>');
            _pendingNotes.add(DocumentBuilder.noteHtml(marker, _noteText(note)));
          }
        case 'drawing':
        case 'pict':
        case 'object':
          for (final id in _imageIds(e)) {
            final img = _image(id);
            if (img != null) content.write(img);
          }
        default:
          break; // rPr, fldChar, instrText, footnoteReference, ...
      }
    }
    if (content.isEmpty) return;
    var out = content.toString();
    if (vertAlign == 'superscript') out = '<sup>$out</sup>';
    if (vertAlign == 'subscript') out = '<sub>$out</sub>';
    if (strike) out = '<s>$out</s>';
    if (underline) out = '<u>$out</u>';
    if (italic) out = '<i>$out</i>';
    if (bold) out = '<b>$out</b>';
    html.write(out);
  }

  /// The paragraphs of a footnote / endnote as one line of HTML.
  String _noteText(XmlElement note) {
    final parts = <String>[];
    for (final para in note.deep('p')) {
      final html = StringBuffer();
      _inline(para, html, StringBuffer(), null);
      final inner = html.toString().trim();
      if (inner.isNotEmpty) parts.add(inner);
    }
    return parts.join('<br>');
  }

  /// Relationship ids of the pictures in a drawing / VML picture.
  Iterable<String> _imageIds(XmlElement e) sync* {
    for (final blip in e.deep('blip')) {
      final id = blip.attr('embed');
      if (id != null) yield id;
    }
    for (final data in e.deep('imagedata')) {
      final id = data.attr('id');
      if (id != null) yield id;
    }
  }

  /// `<img>` for the image with relationship [id], or null if it can't
  /// be shown.
  String? _image(String id) {
    final path = rels[id];
    if (path == null) return null;
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
