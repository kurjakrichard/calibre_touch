import 'dart:typed_data';

import 'txt_text.dart';

/// One paragraph of an RTF document.
class RtfParagraph {
  const RtfParagraph({
    required this.html,
    required this.text,
    this.heading = 0,
    this.title = false,
    this.center = false,
  });

  /// Inline HTML (escaped text, `<b>`, `<i>`, `<u>`, `<br>`, `<img>`).
  final String html;

  /// Plain text.
  final String text;

  /// Heading level 1-6 (from `\outlinelevel` or a "heading N" style),
  /// 0 = normal paragraph.
  final int heading;

  /// The paragraph has the "Title" style.
  final bool title;

  final bool center;
}

/// What [RtfParser.parse] found.
class RtfContent {
  const RtfContent(this.paragraphs, this.info, this.images);

  final List<RtfParagraph> paragraphs;

  /// The `{\info ...}` fields: title, author, subject, keywords, doccomm,
  /// operator, company.
  final Map<String, String> info;

  /// PNG/JPEG pictures by path (`images/1.png`), referenced by the
  /// paragraphs' `<img>` tags.
  final Map<String, Uint8List> images;
}

/// A small RTF reader: text with bold/italic/underline, paragraphs with
/// heading levels and centring, pictures, document info. Handles `\uN`
/// with its `\ucN` fallback characters, `\'hh` in the document's code page
/// (Windows-1250 or 1252), fields (shows the result), and skips fonts,
/// colours, headers/footers, footnotes and every unknown `{\* ...}` group.
///
/// Pure Dart, no exceptions on odd input.
class RtfParser {
  RtfParser._(this._data);

  /// Parses an RTF file. With [maxParagraphs], stops after that many
  /// paragraphs (metadata only needs the start).
  static RtfContent parse(Uint8List data, {int? maxParagraphs}) {
    final parser = RtfParser._(data).._maxParagraphs = maxParagraphs;
    parser._run();
    return RtfContent(parser._paragraphs, parser._info, parser._images);
  }

  /// True if [data] starts like an RTF file.
  static bool isRtf(Uint8List data) =>
      data.length > 5 &&
      data[0] == 0x7B &&
      data[1] == 0x5C &&
      data[2] == 0x72 &&
      data[3] == 0x74 &&
      data[4] == 0x66; // {\rtf

  final Uint8List _data;
  int? _maxParagraphs;
  int _pos = 0;

  final _paragraphs = <RtfParagraph>[];
  final _info = <String, String>{};
  final _images = <String, Uint8List>{};

  // Style number -> (heading level, is title), from the stylesheet.
  final _styleHeading = <int, int>{};
  final _styleTitle = <int>{};

  int _codePage = 1252;
  late _Group _group;
  final _stack = <_Group>[];

  // Text not yet attached to a run (UTF-16 code units).
  final _units = <int>[];
  int _skipFallback = 0;

  // The paragraph being built.
  final _html = StringBuffer();
  final _text = StringBuffer();
  int _parStyle = 0;
  int _parOutline = -1;
  bool _parCenter = false;

  static const _skipDestinations = {
    'fonttbl', 'colortbl', 'header', 'headerl', 'headerr',
    'headerf', 'footer', 'footerl', 'footerr', 'footerf', 'footnote',
    'annotation', 'object', 'nonshppict', 'listtable', 'listoverridetable',
    'rsidtbl', 'generator', 'xmlnstbl', 'themedata', 'colorschememapping',
    'latentstyles', 'datastore', 'mmathPr', 'pgdsctbl', 'filetbl',
    'revtbl', 'fldinst', 'bkmkstart', 'bkmkend', 'txe', 'xe', 'tc',
    'pnseclvl', 'pntext', 'pntxta', 'pntxtb', 'userprops', 'docvar',
    'template', 'comment', 'atnid', 'atnauthor', 'atrfstart', 'atrfend',
    'blipuid', 'picprop',
  };
  static const _infoFields = {
    'title', 'author', 'subject', 'keywords', 'doccomm', 'operator',
    'company',
  };
  static const _paragraphWords = {
    'pard', 's', 'qc', 'ql', 'qr', 'qj', 'outlinelevel', 'par',
  };
  static final _headingStyleName = RegExp(
      r'^(?:heading|címsor|cimsor|überschrift|titre|título|titolo|'
      r'nagłówek|kop|nadpis)\s*(\d)$');

  void _run() {
    _group = _Group.root();
    final n = _data.length;
    while (_pos < n) {
      if (_maxParagraphs != null && _paragraphs.length >= _maxParagraphs!) {
        return;
      }
      final c = _data[_pos];
      if (c == 0x7B) {
        // {
        _flushText();
        _stack.add(_group);
        _group = _Group.child(_group);
        _pos++;
      } else if (c == 0x7D) {
        // }
        _flushText();
        _closeGroup();
        _pos++;
      } else if (c == 0x5C) {
        // backslash
        _pos++;
        if (_pos >= n) break;
        if (_isLetter(_data[_pos])) {
          _controlWord();
        } else {
          _controlSymbol();
        }
      } else {
        _pos++;
        if (c == 0x0A || c == 0x0D) continue;
        _char(c);
      }
    }
    _endParagraph();
  }

  static bool _isLetter(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  void _closeGroup() {
    final g = _group;
    if (g.pictOwner && g.pict != null) _finishPicture(g);
    if (g.styleOwner && g.styleNumber != null) {
      final name = g.styleName
          .toString()
          .trim()
          .replaceFirst(RegExp(r';$'), '')
          .trim()
          .toLowerCase();
      final m = _headingStyleName.firstMatch(name);
      if (g.styleOutline != null && g.styleOutline! < 6) {
        _styleHeading[g.styleNumber!] = g.styleOutline! + 1;
      } else if (m != null) {
        _styleHeading[g.styleNumber!] = int.parse(m.group(1)!);
      }
      if (name == 'title' || name == 'cím' || name == 'titel') {
        _styleTitle.add(g.styleNumber!);
      }
    }
    if (_stack.isNotEmpty) _group = _stack.removeLast();
  }

  void _controlWord() {
    final start = _pos;
    while (_pos < _data.length && _pos - start < 32 && _isLetter(_data[_pos])) {
      _pos++;
    }
    final word = String.fromCharCodes(_data, start, _pos);
    int? arg;
    var negative = false;
    if (_pos < _data.length && _data[_pos] == 0x2D) {
      negative = true;
      _pos++;
    }
    final digitsStart = _pos;
    while (_pos < _data.length &&
        _pos - digitsStart < 10 &&
        _data[_pos] >= 0x30 &&
        _data[_pos] <= 0x39) {
      _pos++;
    }
    if (_pos > digitsStart) {
      arg = int.parse(String.fromCharCodes(_data, digitsStart, _pos));
      if (negative) arg = -arg;
    }
    if (_pos < _data.length && _data[_pos] == 0x20) _pos++; // delimiter
    _word(word, arg);
  }

  void _word(String word, int? arg) {
    final g = _group;

    if (g.ignorable) {
      // {\* ...}: skip, unless it's something we read.
      g.ignorable = false;
      if (word != 'shppict' && word != 'pict') {
        g.dest = _Dest.skip;
        return;
      }
    }
    if (word == 'bin') {
      // Raw binary data: skip it whatever the group is.
      _pos += (arg ?? 0).clamp(0, _data.length - _pos);
      return;
    }
    if (g.dest == _Dest.skip) return;

    // ---- destinations ----
    if (word == 'info') {
      g.dest = _Dest.info;
      return;
    }
    if (g.dest == _Dest.info) {
      if (_infoFields.contains(word)) {
        g
          ..dest = _Dest.infoField
          ..infoName = word;
      }
      return;
    }
    if (word == 'stylesheet') {
      g.dest = _Dest.stylesheet;
      return;
    }
    if (g.dest == _Dest.stylesheet || g.dest == _Dest.style) {
      if (word == 's' && g.dest == _Dest.stylesheet) {
        g
          ..dest = _Dest.style
          ..styleOwner = true
          ..styleNumber = arg ?? 0;
      } else if (word == 'outlinelevel' && g.styleOwner) {
        g.styleOutline = arg;
      }
      return;
    }
    if (word == 'pict') {
      g
        ..dest = _Dest.pict
        ..pictOwner = true
        ..pict = _Picture();
      return;
    }
    if (g.dest == _Dest.pict) {
      if (word == 'pngblip') g.pict?.format = 'png';
      if (word == 'jpegblip') g.pict?.format = 'jpg';
      return;
    }
    if (_skipDestinations.contains(word)) {
      g.dest = _Dest.skip;
      return;
    }
    if (word == 'listtext') {
      // The bullet / number of a list item: keep the text, but its \pard
      // must not reset the paragraph's own style (numbered headings).
      g.listText = true;
      return;
    }
    if (g.listText && _paragraphWords.contains(word)) return;

    // ---- text and formatting ----
    switch (word) {
      case 'ansicpg':
        if (arg != null) _codePage = arg;
      case 'uc':
        g.uc = arg ?? 1;
      case 'u':
        if (arg != null) {
          _addUnit(arg < 0 ? arg + 65536 : arg);
          _skipFallback = g.uc;
        }
      case 'par':
        _endParagraph();
      case 'line':
        _flushText();
        if (g.dest == _Dest.body) {
          _html.write('<br>');
          _text.write(' ');
        }
      case 'tab':
        _addUnit(0x20);
      case 'cell':
        _addUnits(' | '.codeUnits);
      case 'row':
        _endParagraph();
      case 'pard':
        _parStyle = 0;
        _parOutline = -1;
        _parCenter = false;
      case 'qc':
        _parCenter = true;
      case 'ql':
      case 'qr':
      case 'qj':
        _parCenter = false;
      case 's':
        _parStyle = arg ?? 0;
      case 'outlinelevel':
        _parOutline = arg ?? -1;
      case 'b':
        _flushText();
        g.bold = arg != 0;
      case 'i':
        _flushText();
        g.italic = arg != 0;
      case 'ul':
        _flushText();
        g.underline = arg != 0;
      case 'ulnone':
        _flushText();
        g.underline = false;
      case 'plain':
        _flushText();
        g
          ..bold = false
          ..italic = false
          ..underline = false;
      case 'emdash':
        _addUnit(0x2014);
      case 'endash':
        _addUnit(0x2013);
      case 'lquote':
        _addUnit(0x2018);
      case 'rquote':
        _addUnit(0x2019);
      case 'ldblquote':
        _addUnit(0x201C);
      case 'rdblquote':
        _addUnit(0x201D);
      case 'bullet':
        _addUnit(0x2022);
      default:
        break;
    }
  }

  void _controlSymbol() {
    final c = _data[_pos++];
    final g = _group;
    if (c == 0x27) {
      // \'hh
      if (_pos + 2 > _data.length) return;
      final hex = int.tryParse(String.fromCharCodes(_data, _pos, _pos + 2),
          radix: 16);
      _pos += 2;
      if (hex == null || g.dest == _Dest.skip || g.dest == _Dest.pict) return;
      if (_skipFallback > 0) {
        _skipFallback--;
        return;
      }
      _addUnit(TxtText.singleByteChar(hex, _codePage));
      return;
    }
    if (c == 0x2A) {
      // \*
      g.ignorable = true;
      return;
    }
    if (g.dest == _Dest.skip) return;
    switch (c) {
      case 0x5C:
      case 0x7B:
      case 0x7D:
        _char(c);
      case 0x7E:
        _addUnit(0xA0); // \~ non-breaking space
      case 0x5F:
        _addUnit(0x2D); // \_ non-breaking hyphen
      case 0x0A:
      case 0x0D:
        _endParagraph(); // \<newline> = \par
      default:
        break; // \- optional hyphen, \| ...
    }
  }

  void _char(int c) {
    final g = _group;
    if (g.dest == _Dest.skip) return;
    if (g.dest == _Dest.pict) {
      g.pict?.hex.add(c);
      return;
    }
    if (_skipFallback > 0) {
      _skipFallback--;
      return;
    }
    _addUnit(c >= 0x80 ? TxtText.singleByteChar(c, _codePage) : c);
  }

  void _addUnit(int unit) {
    // Symbol-font bullets come through as private-use characters.
    if (unit == 0xF0B7 || unit == 0xF0A7 || unit == 0xF0D8 || unit == 0xF076) {
      unit = 0x2022;
    }
    _units.add(unit);
  }

  void _addUnits(List<int> units) => units.forEach(_addUnit);

  /// Moves the collected characters into the current destination.
  void _flushText() {
    if (_units.isEmpty) return;
    final text = String.fromCharCodes(_units);
    _units.clear();
    final g = _group;
    switch (g.dest) {
      case _Dest.body:
        var html = _escape(text);
        if (g.underline) html = '<u>$html</u>';
        if (g.italic) html = '<i>$html</i>';
        if (g.bold) html = '<b>$html</b>';
        _html.write(html);
        _text.write(text);
      case _Dest.infoField:
        final name = g.infoName!;
        _info[name] = (_info[name] ?? '') + text;
      case _Dest.style:
        if (g.styleOwner) g.styleName.write(text);
      default:
        break;
    }
  }

  void _endParagraph() {
    _flushText();
    final html = _html.toString().trim().replaceFirst(RegExp(r'( \| )+$'), '');
    final text = _text.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    _html.clear();
    _text.clear();
    var heading = 0;
    if (_parOutline >= 0 && _parOutline < 6) {
      heading = _parOutline + 1;
    } else {
      heading = _styleHeading[_parStyle] ?? 0;
    }
    _paragraphs.add(RtfParagraph(
      html: html,
      text: text,
      heading: heading,
      title: _styleTitle.contains(_parStyle),
      center: _parCenter,
    ));
  }

  void _finishPicture(_Group g) {
    final pict = g.pict!;
    final format = pict.format;
    if (format == null) return;
    final hex = pict.hex;
    final bytes = Uint8List(hex.length ~/ 2);
    var count = 0, high = -1;
    for (final c in hex) {
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high < 0) {
        high = v;
      } else {
        bytes[count++] = (high << 4) | v;
        high = -1;
      }
    }
    if (count < 8) return;
    final path = 'images/${_images.length + 1}.$format';
    _images[path] = Uint8List.sublistView(bytes, 0, count);
    // The picture belongs to the paragraph of the enclosing group.
    final parent = _stack.isNotEmpty ? _stack.last : null;
    if (parent == null || parent.dest == _Dest.body) {
      _html.write('<img src="$path">');
    }
  }

  static int _hexValue(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    return -1;
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

enum _Dest { body, skip, info, infoField, stylesheet, style, pict }

class _Picture {
  String? format;
  final hex = <int>[];
}

class _Group {
  _Group.root()
      : bold = false,
        italic = false,
        underline = false,
        uc = 1,
        dest = _Dest.body,
        listText = false;

  _Group.child(_Group parent)
      : bold = parent.bold,
        italic = parent.italic,
        underline = parent.underline,
        uc = parent.uc,
        dest = parent.dest,
        infoName = parent.infoName,
        pict = parent.pict,
        styleNumber = parent.styleNumber,
        listText = parent.listText;

  bool bold;
  bool italic;
  bool underline;
  int uc;
  _Dest dest;
  bool ignorable = false;
  bool listText;
  String? infoName;

  // Stylesheet entry being read (only the group that has the \sN).
  bool styleOwner = false;
  int? styleNumber;
  int? styleOutline;
  final styleName = StringBuffer();

  // Picture being read (owner = the {\pict ...} group itself).
  bool pictOwner = false;
  _Picture? pict;
}
