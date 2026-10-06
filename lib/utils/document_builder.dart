import 'dart:typed_data';
import 'utils.dart';

/// One block of a converted document (DOCX, ODT, RTF): a paragraph,
/// heading, list or table, already as HTML.
class DocBlock {
  const DocBlock(
    this.html, {
    this.text = '',
    this.heading = 0,
    this.paragraph = false,
    this.blanksBefore = 0,
    this.notes = const [],
  });

  /// The block as HTML (`<p>...</p>`, `<h2>...</h2>`, `<ul>...</ul>`, ...).
  final String html;

  /// Plain text of the block (chapter guessing, contents titles).
  final String text;

  /// Heading level from the document's own styles (1 = "Heading 1"),
  /// 0 = not a heading.
  final int heading;

  /// A normal paragraph: may be recognised as a chapter title by its text
  /// ("3. fejezet") when the document has no heading styles.
  final bool paragraph;

  /// Empty paragraphs right before this block.
  final int blanksBefore;

  /// Footnotes referenced in this block, as HTML paragraphs ("<p><sup>
  /// [1]</sup> ...</p>"). Shown at the end of the chapter.
  final List<String> notes;
}

/// Turns [DocBlock]s into an [EpubDocument] the reader can show: one
/// section per chapter, a table of contents, long chapters split by size.
///
/// Chapters are the document's top-level headings ("Heading 1", or
/// "Heading 2" when there is only one "Heading 1" - usually the book
/// title). Documents without heading styles get chapters from paragraphs
/// that look like chapter titles ([ChapterHeading]).
class DocumentBuilder {
  DocumentBuilder._();

  static const int _maxSectionChars = 60000;

  static String _href(int section) =>
      'part${section.toString().padLeft(4, '0')}.html';

  static EpubDocument build(
    List<DocBlock> blocks, {
    Map<String, Uint8List> files = const {},
  }) {
    final headings = [
      for (final b in blocks)
        if (b.heading > 0) b.heading,
    ];
    final guessed = <int>{};
    if (headings.isEmpty) {
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        if (b.paragraph &&
            ChapterHeading.looksLike(b.text, blanksBefore: b.blanksBefore)) {
          guessed.add(i);
        }
      }
    }

    // The level that starts a chapter, and the deepest one in the contents.
    var chapterLevel = 1;
    if (headings.isNotEmpty) {
      headings.sort();
      chapterLevel = headings.first;
      final top = headings.where((h) => h == chapterLevel).length;
      final deeper = headings.where((h) => h > chapterLevel).toList();
      if (top <= 1 && deeper.isNotEmpty) chapterLevel = deeper.first;
    }
    final tocLevel = chapterLevel + 1;

    final sections = <EpubSection>[];
    final toc = <EpubTocEntry>[];
    final current = StringBuffer();
    final notes = <String>[];

    void closeSection() {
      if (current.isEmpty) return;
      if (notes.isNotEmpty) {
        current
          ..write('<hr>')
          ..write(notes.join());
        notes.clear();
      }
      sections.add(EpubSection(
          href: _href(sections.length), html: current.toString()));
      current.clear();
    }

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final level = guessed.contains(i) ? chapterLevel : b.heading;
      var html = b.html;
      if (guessed.contains(i)) html = '<h2>${escape(b.text)}</h2>';

      if (level > 0 && level <= chapterLevel) {
        closeSection();
      } else if (current.length > _maxSectionChars) {
        closeSection();
      }
      if (level > 0 && level <= tocLevel && b.text.trim().isNotEmpty) {
        toc.add(EpubTocEntry(
          title: b.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          href: _href(sections.length),
          sectionIndex: sections.length,
          depth: level <= chapterLevel ? 0 : level - chapterLevel,
        ));
      }
      current.write(html);
      notes.addAll(b.notes);
    }
    closeSection();
    if (sections.isEmpty) {
      throw const FormatException('The document has no readable content');
    }
    return EpubDocument.fromParts(
      // The reader shows the library's title/author.
      title: '',
      author: '',
      sections: sections,
      toc: toc,
      files: files,
    );
  }

  /// A footnote as shown at the end of a chapter.
  static String noteHtml(String marker, String html) =>
      '<p style="font-size:85%"><sup>$marker</sup> $html</p>';

  /// HTML-escapes text.
  static String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// True for images Flutter can show (JPEG, PNG, GIF, BMP, WebP) - not
  /// EMF/WMF/TIFF, which Word documents sometimes contain.
  static bool isDisplayableImage(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true; // PNG
    }
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    if (b[0] == 0x42 && b[1] == 0x4D) return true; // BMP
    return b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50; // WebP
  }
}

/// Recognises chapter titles in plain text: "Chapter 12", "CHAPTER IV.
/// The Storm", "Part Two", "3. fejezet", "Második rész", "Prologue",
/// "Előszó", a bare "IV.", and (after two blank lines) an all-caps line.
/// Used for TXT files and for DOCX/ODT/RTF without heading styles.
class ChapterHeading {
  ChapterHeading._();

  static const _number =
      r'(?:\d{1,3}|[IVXLCDM]{1,7}|one|two|three|four|five|six|seven|eight|'
      r'nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|'
      r'eighteen|nineteen|twenty|thirty|forty|fifty|first|second|third|'
      r'fourth|fifth|sixth|seventh|eighth|ninth|tenth|eins|zwei|drei)';

  // "Chapter 12", "PART TWO: The Return", "Kapitel 3"
  static final _numbered = RegExp(
      r'^(?:chapter|part|book|volume|section|appendix|fejezet|rész|könyv|'
      r'kötet|kapitel|teil|buch|chapitre|partie|livre)\s+'
      '$_number'
      r'\b\.?(.*)$',
      caseSensitive: false,
      unicode: true);

  // "3. fejezet", "IV. rész", "Második könyv"
  static final _numberFirst = RegExp(
      r'^(?:\d{1,3}|[IVXLCDM]{1,7}|\p{L}+(?:dik|ső))\.?\s+'
      r'(?:fejezet|rész|könyv|kötet|kapitel|teil)(?![\p{L}])\.?(.*)$',
      caseSensitive: false,
      unicode: true);

  // "Prologue", "Előszó", "Epilogue: Ten Years Later"
  static final _alone = RegExp(
      r'^(?:prologue|epilogue|introduction|preface|foreword|afterword|'
      r'előszó|utószó|bevezetés|bevezető|epilógus|prológus|zárszó|vorwort|'
      r'nachwort|einleitung|prolog|epilog)\.?(?:\s*[:\-–—]\s*.{1,60})?$',
      caseSensitive: false,
      unicode: true);

  // "IV." / "12" alone on a line
  static final _bare = RegExp(r'^(?:\d{1,3}|[IVXLCDM]{1,7})\.?$');

  // "IV. The Storm" (only after a blank line)
  static final _numberTitle =
      RegExp(r'^(?:\d{1,3}|[IVXLCDM]{1,7})\.\s+\S.{0,50}$');

  // What may follow "Chapter 12": nothing, ". Title" / ": Title" /
  // " - Title", or " Title" with a capital letter (not "Chapter 1 was").
  static final _titleTail = RegExp(
      r'''^(?:|\s*[.:\-–—]\s*.{0,60}|\s+["„“'(\p{Lu}\d].{0,60})$''',
      unicode: true);

  static final _sceneBreak = RegExp(r'^[\s*#~=\-]{3,}$');

  /// Whether the one-line paragraph [line] looks like a chapter title.
  /// [blanksBefore] = empty lines/paragraphs right before it.
  static bool looksLike(String line, {int blanksBefore = 0}) {
    final l = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (l.isEmpty || l.length > 70 || _sceneBreak.hasMatch(l)) return false;
    for (final re in [_numbered, _numberFirst]) {
      final m = re.firstMatch(l);
      if (m != null && _titleTail.hasMatch(m.group(1)!)) return true;
    }
    if (_alone.hasMatch(l) || _bare.hasMatch(l)) return true;
    if (blanksBefore >= 1 &&
        _numberTitle.hasMatch(l) &&
        !RegExp(r'[.,;!?]$').hasMatch(l)) {
      return true;
    }
    // An all-caps line set off by two or more blank lines.
    return blanksBefore >= 2 && _isUpperCase(l) && !RegExp(r'[,;]$').hasMatch(l);
  }

  static bool _isUpperCase(String s) {
    var letters = 0;
    for (final ch in s.split('')) {
      if (ch.toLowerCase() == ch.toUpperCase()) continue;
      if (ch != ch.toUpperCase()) return false;
      letters++;
    }
    return letters >= 2;
  }
}

/// Builds nested `<ul>`/`<ol>` HTML from list items with levels (0 = top).
/// A level can only go one deeper than the previous item.
class NestedList {
  final _html = StringBuffer();
  final _open = <String>[]; // tags of the open lists

  bool get isEmpty => _html.isEmpty;

  /// Adds an item at [level] in a list of kind [tag] (`ul` / `ol`).
  void add(int level, String tag, String content) {
    var l = level < 0 ? 0 : level;
    if (l > _open.length) l = _open.length;
    while (_open.length > l + 1) {
      _html.write('</li></${_open.removeLast()}>');
    }
    if (_open.length == l + 1) {
      _html.write('</li>');
      if (_open.last != tag) {
        // Another kind of list at the same level: close and reopen.
        _html.write('</${_open.removeLast()}><$tag>');
        _open.add(tag);
      }
    } else {
      _html.write('<$tag>');
      _open.add(tag);
    }
    _html.write('<li>$content');
  }

  /// The HTML so far, all lists closed; the builder is emptied.
  String finish() {
    while (_open.isNotEmpty) {
      _html.write('</li></${_open.removeLast()}>');
    }
    final out = _html.toString();
    _html.clear();
    return out;
  }
}
