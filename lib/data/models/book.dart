// ignore_for_file: non_constant_identifier_names
import 'package:equatable/equatable.dart';
import '../../utils/utils.dart';

class Book extends Equatable {
  final int? id;
  final String title;
  final String author;
  final String price;
  final String image;
  final String path;
  final String filename;
  final String format;
  final String last_modified;
  final String description;
  final double rating;
  final int pages;

  /// Calibre publisher (publishers + books_publishers_link), '' = none.
  final String publisher;

  /// Calibre series name (series + books_series_link), '' = none.
  final String series;

  /// Position in [series] (books.series_index), e.g. 1, 2, 2.5.
  final double series_index;

  /// Calibre tags (tags + books_tags_link), comma separated: 'Fantasy, Epic'.
  final String tags;

  /// Publication date (books.pubdate) in Calibre's timestamp format,
  /// '' = unknown.
  final String pubdate;

  /// Calibre language codes (languages + books_languages_link), comma
  /// separated: 'eng, hun'.
  final String languages;

  /// Calibre identifiers (identifiers table) as Calibre shows them:
  /// 'isbn:9781968707651, goodreads:245804344'.
  final String identifiers;

  const Book(
      {this.id,
      required this.title,
      required this.author,
      required this.price,
      required this.image,
      required this.path,
      required this.filename,
      required this.format,
      required this.last_modified,
      required this.description,
      required this.rating,
      required this.pages,
      this.publisher = '',
      this.series = '',
      this.series_index = 1.0,
      this.tags = '',
      this.pubdate = '',
      this.languages = '',
      this.identifiers = ''});

  /// [tags] as a list (trimmed, empty entries dropped).
  List<String> get tagList => splitTags(tags);

  /// Splits a comma separated tag string, dropping blanks and duplicates
  /// (case-insensitive, first spelling wins) - the way Calibre does.
  static List<String> splitTags(String value) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in value.split(',')) {
      final tag = raw.trim();
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
      result.add(tag);
    }
    return result;
  }

  /// [languages] as a list: ['eng', 'hun'].
  List<String> get languageList => languages
      .split(',')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  /// [identifiers] as a map: {isbn: 978..., goodreads: 245804344}.
  Map<String, String> get identifierMap => parseIdentifiers(identifiers);

  /// 'isbn:1, goodreads:2' -> {isbn: 1, goodreads: 2}
  static Map<String, String> parseIdentifiers(String value) {
    final result = <String, String>{};
    for (final part in value.split(',')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      final type = part.substring(0, colon).trim().toLowerCase();
      final val = part.substring(colon + 1).trim();
      if (type.isNotEmpty && val.isNotEmpty) result[type] = val;
    }
    return result;
  }

  /// {isbn: 1, goodreads: 2} -> 'isbn:1, goodreads:2'
  static String joinIdentifiers(Map<String, String> identifiers) =>
      identifiers.entries.map((e) => '${e.key}:${e.value}').join(', ');

  /// Series with its number, e.g. 'The Wheel of Time [2]' ('' = no series).
  String get seriesLabel =>
      series.isEmpty ? '' : '$series [${formatSeriesIndex(series_index)}]';

  /// 2.0 -> '2', 2.5 -> '2.5'
  static String formatSeriesIndex(double index) =>
      index == index.roundToDouble() ? index.toInt().toString() : '$index';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      Bookkeys.id.name: id,
      Bookkeys.title.name: title,
      Bookkeys.author.name: author,
      Bookkeys.price.name: price,
      Bookkeys.image.name: image,
      Bookkeys.path.name: path,
      Bookkeys.filename.name: filename,
      Bookkeys.format.name: format,
      Bookkeys.last_modified.name: last_modified,
      Bookkeys.description.name: description,
      Bookkeys.rating.name: rating,
      Bookkeys.pages.name: pages,
      Bookkeys.publisher.name: publisher,
      Bookkeys.series.name: series,
      Bookkeys.series_index.name: series_index,
      Bookkeys.tags.name: tags,
      Bookkeys.pubdate.name: pubdate,
      Bookkeys.languages.name: languages,
      Bookkeys.identifiers.name: identifiers,
    };
  }

  factory Book.fromJson(Map<String, dynamic> map) {
    return Book(
      id: map[Bookkeys.id.name],
      title: map[Bookkeys.title.name],
      author: map[Bookkeys.author.name],
      price: map[Bookkeys.price.name],
      image: map[Bookkeys.image.name],
      path: map[Bookkeys.path.name],
      filename: map[Bookkeys.filename.name],
      format: map[Bookkeys.format.name],
      last_modified: map[Bookkeys.last_modified.name],
      description: map[Bookkeys.description.name],
      rating: map[Bookkeys.rating.name],
      pages: map[Bookkeys.pages.name],
      publisher: map[Bookkeys.publisher.name] as String? ?? '',
      series: map[Bookkeys.series.name] as String? ?? '',
      series_index:
          (map[Bookkeys.series_index.name] as num?)?.toDouble() ?? 1.0,
      tags: map[Bookkeys.tags.name] as String? ?? '',
      pubdate: map[Bookkeys.pubdate.name] as String? ?? '',
      languages: map[Bookkeys.languages.name] as String? ?? '',
      identifiers: map[Bookkeys.identifiers.name] as String? ?? '',
    );
  }

  @override
  List<Object> get props {
    return [
      title,
      author,
      price,
      image,
      path,
      filename,
      format,
      last_modified,
      description,
      rating,
      pages,
      publisher,
      series,
      series_index,
      tags,
      pubdate,
      languages,
      identifiers,
    ];
  }

  /// Short form for logs (e.g. the Riverpod observer). The description
  /// (comments.text, often long HTML) is left out on purpose - only its
  /// length is shown.
  @override
  String toString() => 'Book(id: $id, title: $title, author: $author, '
      'path: $path, format: $format, pages: $pages, rating: $rating, '
      'publisher: $publisher, series: $series [$series_index], tags: $tags, '
      'pubdate: $pubdate, languages: $languages, identifiers: $identifiers, '
      'description: ${description.length} chars)';

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? price,
    String? image,
    String? path,
    String? filename,
    String? format,
    String? last_modified,
    String? description,
    double? rating,
    int? pages,
    String? publisher,
    String? series,
    double? series_index,
    String? tags,
    String? pubdate,
    String? languages,
    String? identifiers,
  }) {
    return Book(
        id: id ?? this.id,
        title: title ?? this.title,
        author: author ?? this.author,
        price: price ?? this.price,
        image: image ?? this.image,
        path: path ?? this.path,
        filename: filename ?? this.filename,
        format: format ?? this.format,
        last_modified: last_modified ?? this.last_modified,
        description: description ?? this.description,
        rating: rating ?? this.rating,
        pages: pages ?? this.pages,
        publisher: publisher ?? this.publisher,
        series: series ?? this.series,
        series_index: series_index ?? this.series_index,
        tags: tags ?? this.tags,
        pubdate: pubdate ?? this.pubdate,
        languages: languages ?? this.languages,
        identifiers: identifiers ?? this.identifiers);
  }
}
