import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import 'calibre.dart';

/// Metadata read from a book file (EPUB, PDF, ...) by a [MetadataReader].
///
/// Plain data only, so it can be sent between isolates. Empty strings /
/// lists and null mean "not found in the file".
class BookMetadata {
  const BookMetadata({
    this.title = '',
    this.titleSort = '',
    this.authors = const [],
    this.authorSort = '',
    this.publisher = '',
    this.pubdate,
    this.description = '',
    this.series = '',
    this.seriesIndex,
    this.tags = const [],
    this.languages = const [],
    this.identifiers = const {},
    this.rating,
    this.pageCount,
    this.cover,
    this.format = '',
  });

  final String title;

  /// Sort form of the title if the file has one (OPF file-as /
  /// calibre:title_sort), otherwise ''.
  final String titleSort;

  /// One entry per author, in the file's order.
  final List<String> authors;

  /// Author sort from the file (OPF file-as), '' if none.
  final String authorSort;

  final String publisher;

  /// Publication date.
  final DateTime? pubdate;

  /// Description / blurb. HTML when the file has HTML (EPUB), else text.
  final String description;

  final String series;
  final double? seriesIndex;

  final List<String> tags;

  /// Calibre 3-letter language codes (`eng`, `hun`, ...).
  final List<String> languages;

  /// Calibre identifiers: type -> value, e.g. {isbn: 978..., goodreads: 123}.
  final Map<String, String> identifiers;

  /// Calibre rating 0-10 (stars x 2).
  final int? rating;

  /// Number of pages, if the format has real pages (PDF).
  final int? pageCount;

  /// The cover as JPEG bytes, ready to be saved as cover.jpg.
  final Uint8List? cover;

  /// File format as Calibre stores it in `data.format`: EPUB, PDF, ...
  final String format;

  /// Title/author guessed from the file name, the way Calibre does when a
  /// file has no metadata: "Title - Author.epub". Underscores count as
  /// spaces.
  factory BookMetadata.fromFileName(String filePath) {
    final name = p.basenameWithoutExtension(filePath).replaceAll('_', ' ');
    final clean = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    final format =
        p.extension(filePath).replaceFirst('.', '').toUpperCase();
    final match = RegExp(r'^(.+?) - (.+)$').firstMatch(clean);
    if (match == null) return BookMetadata(title: clean, format: format);
    return BookMetadata(
      title: match.group(1)!.trim(),
      authors: Calibre.stringToAuthors(match.group(2)!),
      format: format,
    );
  }

  /// This metadata with every empty field taken from [other].
  BookMetadata mergedWith(BookMetadata other) => BookMetadata(
        title: title.isNotEmpty ? title : other.title,
        titleSort: title.isNotEmpty ? titleSort : other.titleSort,
        authors: authors.isNotEmpty ? authors : other.authors,
        authorSort: authors.isNotEmpty ? authorSort : other.authorSort,
        publisher: publisher.isNotEmpty ? publisher : other.publisher,
        pubdate: pubdate ?? other.pubdate,
        description: description.isNotEmpty ? description : other.description,
        series: series.isNotEmpty ? series : other.series,
        seriesIndex: series.isNotEmpty ? seriesIndex : other.seriesIndex,
        tags: tags.isNotEmpty ? tags : other.tags,
        languages: languages.isNotEmpty ? languages : other.languages,
        identifiers: {...other.identifiers, ...identifiers},
        rating: rating ?? other.rating,
        pageCount: pageCount ?? other.pageCount,
        cover: cover ?? other.cover,
        format: format.isNotEmpty ? format : other.format,
      );

  BookMetadata copyWith({
    String? title,
    String? titleSort,
    List<String>? authors,
    String? authorSort,
    String? publisher,
    DateTime? pubdate,
    String? description,
    String? series,
    double? seriesIndex,
    List<String>? tags,
    List<String>? languages,
    Map<String, String>? identifiers,
    int? rating,
    int? pageCount,
    Uint8List? cover,
    String? format,
  }) =>
      BookMetadata(
        title: title ?? this.title,
        titleSort: titleSort ?? this.titleSort,
        authors: authors ?? this.authors,
        authorSort: authorSort ?? this.authorSort,
        publisher: publisher ?? this.publisher,
        pubdate: pubdate ?? this.pubdate,
        description: description ?? this.description,
        series: series ?? this.series,
        seriesIndex: seriesIndex ?? this.seriesIndex,
        tags: tags ?? this.tags,
        languages: languages ?? this.languages,
        identifiers: identifiers ?? this.identifiers,
        rating: rating ?? this.rating,
        pageCount: pageCount ?? this.pageCount,
        cover: cover ?? this.cover,
        format: format ?? this.format,
      );

  /// Short form for logs - the cover is shown by size, the description
  /// by length.
  @override
  String toString() => 'BookMetadata(format: $format, title: $title, '
      'authors: $authors, publisher: $publisher, pubdate: $pubdate, '
      'series: $series [$seriesIndex], tags: $tags, languages: $languages, '
      'identifiers: $identifiers, rating: $rating, pages: $pageCount, '
      'description: ${description.length} chars, '
      'cover: ${cover == null ? 'none' : '${cover!.length} bytes'})';
}
