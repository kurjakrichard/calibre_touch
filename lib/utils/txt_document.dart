import 'dart:typed_data';
import '../metadata/readers/txt_text.dart';
import 'utils.dart';

/// Opens plain-text (.txt) books for the built-in reader by turning them
/// into an [EpubDocument]:
/// - encoding detected by [TxtText.decode] (UTF-8/16, Windows-1250/1252);
/// - Project Gutenberg licence header/footer removed;
/// - paragraphs: blocks between blank lines (hard-wrapped lines joined),
///   or indented lines, or one paragraph per line - whichever the file
///   uses; short lines (verse, addresses) keep their line breaks;
/// - chapters: lines like "Chapter 1", "CHAPTER XII. The End", "Part
///   Two", "3. fejezet", "Második rész", "Prologue", "Előszó", "IV.",
///   or an all-caps line after two blank lines. They start a new section
///   and make up the table of contents. Long stretches without a heading
///   are split by size.
///
/// Pure Dart: call [TxtDocument.parse] through `compute`.
class TxtDocument {
  TxtDocument._();

  static const extensions = {'txt'};

  /// A section is closed at the next paragraph once it is this long.
  static const int _maxSectionChars = 60000;

  static String _href(int section) =>
      'part${section.toString().padLeft(4, '0')}.html';

  static Future<EpubDocument> parse(Uint8List bytes) async {
    final text = TxtText.stripGutenberg(TxtText.decode(bytes));
    final paragraphs = _paragraphs(text);
    if (paragraphs.isEmpty) {
      throw const FormatException('The file is empty');
    }

    final sections = <EpubSection>[];
    final toc = <EpubTocEntry>[];
    final current = StringBuffer();

    void closeSection() {
      if (current.isEmpty) return;
      sections.add(EpubSection(
          href: _href(sections.length), html: current.toString()));
      current.clear();
    }

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];
      if (_isHeading(para)) {
        var title = para.lines.first;
        var html = '<h2>${_escape(title)}</h2>';
        // A chapter title on the next short line: "CHAPTER I." "The Period"
        if (i + 1 < paragraphs.length) {
          final next = paragraphs[i + 1];
          final sub = next.lines.first;
          if (next.lines.length == 1 &&
              sub.length <= 60 &&
              !RegExp(r'[.!?,]$').hasMatch(sub) &&
              !_isHeading(next) &&
              !_byLine.hasMatch(sub)) {
            i++;
            title = RegExp(r'[.:]$').hasMatch(title)
                ? '$title $sub'
                : '$title. $sub';
            html = '<h2>${_escape(para.lines.first)}<br>${_escape(sub)}</h2>';
          }
        }
        closeSection();
        toc.add(EpubTocEntry(
          title: title,
          href: _href(sections.length),
          sectionIndex: sections.length,
          depth: 0,
        ));
        current.write(html);
        continue;
      }

      if (current.length > _maxSectionChars) closeSection();
      current.write(_paragraphHtml(para));
    }
    closeSection();

    // No title/author in a text file: the reader shows the library's.
    return EpubDocument.fromParts(
      title: '',
      author: '',
      sections: sections,
      toc: toc,
      files: const {},
    );
  }

  // ---------------------------------------------------------------------
  // Paragraphs
  // ---------------------------------------------------------------------

  static List<_Paragraph> _paragraphs(String text) {
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    var nonBlank = 0, indented = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      nonBlank++;
      if (line.startsWith(' ') || line.startsWith('\t')) indented++;
    }
    final blank = lines.length - nonBlank;
    final _Mode mode;
    if (nonBlank > 0 && blank >= 2 && blank >= nonBlank * 0.1) {
      mode = _Mode.blankLines;
    } else if (nonBlank > 0 &&
        indented >= nonBlank * 0.2 &&
        indented <= nonBlank * 0.8) {
      mode = _Mode.indent;
    } else {
      mode = _Mode.line;
    }

    final out = <_Paragraph>[];
    var current = <String>[];
    var blanks = 0;
    var blanksBefore = 0;

    void flush() {
      if (current.isNotEmpty) out.add(_Paragraph(current, blanksBefore));
      current = <String>[];
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flush();
        blanks++;
        continue;
      }
      if (mode == _Mode.line ||
          (mode == _Mode.indent &&
              (line.startsWith(' ') || line.startsWith('\t')))) {
        flush();
      }
      if (current.isEmpty) {
        blanksBefore = blanks;
        blanks = 0;
      }
      current.add(trimmed.replaceAll(RegExp(r'\s+'), ' '));
      if (mode == _Mode.line) flush();
    }
    flush();
    return out;
  }

  static final _sceneBreak = RegExp(r'^[\s*#~=\-]{3,}$');

  static String _paragraphHtml(_Paragraph para) {
    final lines = para.lines;
    if (lines.length == 1 && _sceneBreak.hasMatch(lines.first)) {
      return '<p style="text-align:center">* * *</p>';
    }
    // Mostly short lines = verse / letters: keep the line breaks.
    // Otherwise the lines were wrapped by the file and are joined.
    var short = 0;
    for (var i = 0; i < lines.length - 1; i++) {
      if (lines[i].length < 45) short++;
    }
    final keepBreaks = lines.length > 1 && short > (lines.length - 1) / 2;
    final html = keepBreaks
        ? lines.map(_escape).join('<br>')
        : _escape(lines.join(' '));
    return '<p>$html</p>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // ---------------------------------------------------------------------
  // Chapter headings (rules shared with DOCX/ODT/RTF: [ChapterHeading])
  // ---------------------------------------------------------------------

  static final _byLine =
      RegExp(r'^(by|írta|irta|von)\s', caseSensitive: false);

  static bool _isHeading(_Paragraph para) =>
      para.lines.length == 1 &&
      ChapterHeading.looksLike(para.lines.first,
          blanksBefore: para.blanksBefore);
}

enum _Mode { blankLines, indent, line }

class _Paragraph {
  const _Paragraph(this.lines, this.blanksBefore);
  final List<String> lines;

  /// Blank lines right before this paragraph.
  final int blanksBefore;
}
