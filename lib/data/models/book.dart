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
      this.tags = ''});

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
    ];
  }

  /// Short form for logs (e.g. the Riverpod observer). The description
  /// (comments.text, often long HTML) is left out on purpose - only its
  /// length is shown.
  @override
  String toString() => 'Book(id: $id, title: $title, author: $author, '
      'path: $path, format: $format, pages: $pages, rating: $rating, '
      'publisher: $publisher, series: $series [$series_index], tags: $tags, '
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
        tags: tags ?? this.tags);
  }
}
