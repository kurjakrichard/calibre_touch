import 'package:flutter/foundation.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../../data/data_export.dart';

/// Search index over one list of books: title, author, publisher, series,
/// tags and description, case- and accent-insensitive; every word of the
/// query must match.
///
/// Preparing the text (removing accents, stripping the description's HTML)
/// is the slow part, so [build] does it once, in a background isolate.
/// [filter] is then only plain `contains` checks.
class BookSearch {
  BookSearch._(this.books, this._texts);

  /// The books this index was built for (same order as [_texts]).
  final List<Book> books;
  final List<String> _texts;

  static Future<BookSearch> build(List<Book> books) async {
    final raw = [
      for (final b in books)
        '${b.title}\n${b.author}\n${b.publisher}\n${b.series}\n'
            '${b.tags}\n${b.description}',
    ];
    final texts = await compute(_normalizeAll, raw);
    return BookSearch._(books, texts);
  }

  /// Books matching [query] ([books] itself for an empty query).
  List<Book> filter(String query) {
    final words = queryWords(query);
    if (words.isEmpty) return books;
    final result = <Book>[];
    for (var i = 0; i < books.length; i++) {
      final text = _texts[i];
      if (words.every(text.contains)) result.add(books[i]);
    }
    return result;
  }

  /// The normalized words of [query] (empty = nothing to search for).
  static List<String> queryWords(String query) => normalize(query)
      .split(_whitespace)
      .where((w) => w.isNotEmpty)
      .toList();

  static String normalize(String s) => removeDiacritics(s).toLowerCase();
}

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _htmlTag = RegExp(r'<[^>]*>');
final RegExp _htmlEntity = RegExp(r'&#?[a-zA-Z0-9]+;');

/// Runs in the isolate. The description is Calibre HTML: tags and entities
/// are dropped so they don't produce false matches ("div", "span").
List<String> _normalizeAll(List<String> raw) => [
      for (final s in raw)
        BookSearch.normalize(s
            .replaceAll(_htmlTag, ' ')
            .replaceAll(_htmlEntity, ' ')
            .replaceAll(_whitespace, ' ')),
    ];
