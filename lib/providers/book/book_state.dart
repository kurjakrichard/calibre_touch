import 'package:equatable/equatable.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../../data/data_export.dart';

class BookState extends Equatable {
  /// Every book in the library.
  final List<Book> books;

  /// Current search text from the app bar ('' = no search).
  final String query;

  const BookState({
    required this.books,
    this.query = '',
  });
  const BookState.initial({
    this.books = const [],
    this.query = '',
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
  }) {
    return BookState(
      books: books ?? this.books,
      query: query ?? this.query,
    );
  }

  BookState update({
    List<Book>? books,
    String? query,
  }) {
    return copyWith(books: books, query: query);
  }

  @override
  List<Object> get props => [books, query];
}
