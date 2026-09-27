import 'package:equatable/equatable.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../../data/data_export.dart';

class BookState extends Equatable {
  /// Every book in the library.
  final List<Book> books;

  /// Current search text from the app bar ('' = no search).
  final String query;

  /// Absolute folder the [books] were loaded from. Stored together with the
  /// books so covers are never resolved against a different library than
  /// the list they belong to (null until the first load finishes).
  final String? libraryRoot;

  const BookState({
    required this.books,
    this.query = '',
    this.libraryRoot,
  });
  const BookState.initial({
    this.books = const [],
    this.query = '',
    this.libraryRoot,
  });

  /// The books to show: all of them, or only those matching [query]
  /// (title, author or description; case- and accent-insensitive, every
  /// word of the query must match).
  List<Book> get visibleBooks {
    final words = _normalize(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return books;
    return books.where((book) {
      final haystack =
          _normalize('${book.title} ${book.author} ${book.description}');
      return words.every(haystack.contains);
    }).toList();
  }

  static String _normalize(String s) => removeDiacritics(s).toLowerCase();

  BookState copyWith({
    List<Book>? books,
    String? query,
    String? libraryRoot,
  }) {
    return BookState(
      books: books ?? this.books,
      query: query ?? this.query,
      libraryRoot: libraryRoot ?? this.libraryRoot,
    );
  }

  BookState update({
    List<Book>? books,
    String? query,
  }) {
    return copyWith(books: books, query: query);
  }

  @override
  List<Object?> get props => [books, query, libraryRoot];
}
