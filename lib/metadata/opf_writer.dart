/// One author of an [OpfBook]: name and sort form (authors.name / .sort).
class OpfAuthor {
  const OpfAuthor(this.name, this.sort);
  final String name;
  final String sort;
}

/// Everything Calibre puts into a book's metadata.opf. Field values are
/// in the form Calibre keeps them in metadata.db (timestamps as
/// `2026-10-03 13:13:37.697500+00:00`, rating 0-10, language codes, ...).
class OpfBook {
  const OpfBook({
    required this.id,
    required this.uuid,
    required this.title,
    required this.titleSort,
    required this.authors,
    this.authorSort = '',
    this.timestamp = '',
    this.pubdate = '',
    this.publisher = '',
    this.description = '',
    this.series = '',
    this.seriesIndex = 1.0,
    this.rating = 0,
    this.tags = const [],
    this.languages = const [],
    this.identifiers = const {},
    this.hasCover = false,
  });

  final int id;
  final String uuid;
  final String title;
  final String titleSort;
  final List<OpfAuthor> authors;

  /// books.author_sort.
  final String authorSort;
  final String timestamp;

  /// '' or Calibre's undefined date = no date.
  final String pubdate;
  final String publisher;

  /// HTML (comments.text).
  final String description;
  final String series;
  final double seriesIndex;
  final int rating;
  final List<String> tags;
  final List<String> languages;
  final Map<String, String> identifiers;
  final bool hasCover;
}

/// Writes the `metadata.opf` Calibre keeps in every book folder (OPF 2.0,
/// the same layout Calibre itself writes). Calibre's "Restore database"
/// rebuilds metadata.db from these files.
class OpfWriter {
  OpfWriter._();

  /// Name of the file in the book folder.
  static const String fileName = 'metadata.opf';

  static String write(OpfBook book, {String generator = 'Calibre Touch'}) {
    final out = StringBuffer()
      ..writeln("<?xml version='1.0' encoding='utf-8'?>")
      ..writeln('<package xmlns="http://www.idpf.org/2007/opf" '
          'unique-identifier="uuid_id" version="2.0">')
      ..writeln('    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:opf="http://www.idpf.org/2007/opf">');

    void line(String xml) => out.writeln('        $xml');
    void meta(String name, String content) =>
        line('<meta name="${_attr(name)}" content="${_attr(content)}"/>');

    line('<dc:identifier opf:scheme="calibre" id="calibre_id">${book.id}'
        '</dc:identifier>');
    line('<dc:identifier opf:scheme="uuid" id="uuid_id">${_text(book.uuid)}'
        '</dc:identifier>');
    line('<dc:title>${_text(book.title)}</dc:title>');
    for (final author in book.authors) {
      final fileAs = author.sort.isEmpty ? '' : ' opf:file-as="${_attr(author.sort)}"';
      line('<dc:creator$fileAs opf:role="aut">${_text(author.name)}</dc:creator>');
    }
    line('<dc:contributor opf:file-as="calibre" opf:role="bkp">'
        '${_text(generator)}</dc:contributor>');
    final pubdate = _isoDate(book.pubdate);
    if (pubdate != null) line('<dc:date>$pubdate</dc:date>');
    if (book.description.trim().isNotEmpty) {
      line('<dc:description>${_text(book.description.trim())}</dc:description>');
    }
    if (book.publisher.isNotEmpty) {
      line('<dc:publisher>${_text(book.publisher)}</dc:publisher>');
    }
    for (final entry in book.identifiers.entries) {
      line('<dc:identifier opf:scheme="${_attr(entry.key.toUpperCase())}">'
          '${_text(entry.value)}</dc:identifier>');
    }
    for (final language in book.languages) {
      line('<dc:language>${_text(language)}</dc:language>');
    }
    for (final tag in book.tags) {
      line('<dc:subject>${_text(tag)}</dc:subject>');
    }
    if (book.series.isNotEmpty) {
      meta('calibre:series', book.series);
      meta('calibre:series_index', _number(book.seriesIndex));
    }
    if (book.rating > 0) meta('calibre:rating', '${book.rating}');
    final timestamp = _isoDate(book.timestamp);
    if (timestamp != null) meta('calibre:timestamp', timestamp);
    meta('calibre:title_sort', book.titleSort);

    out.writeln('    </metadata>');
    if (book.hasCover) {
      out
        ..writeln('    <guide>')
        ..writeln('        <reference type="cover" title="Cover" '
            'href="cover.jpg"/>')
        ..writeln('    </guide>');
    }
    out.writeln('</package>');
    return out.toString();
  }

  /// `2026-10-03 13:13:37+00:00` -> `2026-10-03T13:13:37+00:00`; null for
  /// empty / Calibre's undefined date.
  static String? _isoDate(String value) {
    final v = value.trim();
    if (v.isEmpty || v.compareTo('0102') < 0) return null;
    return v.replaceFirst(' ', 'T');
  }

  static String _number(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(1) : '$v';

  static String _text(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      // characters XML 1.0 does not allow
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _attr(String s) => _text(s).replaceAll('"', '&quot;');
}
