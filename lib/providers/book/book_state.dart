import 'package:equatable/equatable.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../../data/data_export.dart';

/// Why the library could not be loaded.
class LibraryLoadError extends Equatable {
  /// Android: the app has no "All files access" for the custom folder.
  final bool needsStoragePermission;

  /// Technical error text (empty for [needsStoragePermission]).
  final String message;

  const LibraryLoadError.storagePermission()
      : needsStoragePermission = true,
        message = '';
  const LibraryLoadError.failed(this.message) : needsStoragePermission = false;

  @override
  List<Object?> get props => [needsStoragePermission, message];
}

class BookState extends Equatable {
  /// Every book in the library.
  final List<Book> books;

  /// Current search text from the app bar ('' = no search).
  final String query;

  /// Absolute folder the [books] were loaded from. Stored together with the
  /// books so covers are never resolved against a different library than
  /// the list they belong to (null until the first load finishes).
  final String? libraryRoot;

  /// Set when the last load failed (null = loaded fine / still loading).
  final LibraryLoadError? error;

  /// True once the first load of this library finished (ok or failed).
  final bool loaded;

  const BookState({
    required this.books,
    this.query = '',
    this.libraryRoot,
    this.error,
    this.loaded = false,
  });
  const BookState.initial({
    this.books = const [],
    this.query = '',
    this.libraryRoot,
    this.error,
    this.loaded = false,
  });

  /// The books to show: all of them, or only those matching [query]
  /// (title, author, publisher, series, tags or description; case- and
  /// accent-insensitive, every word of the query must match).
  List<Book> get visibleBooks {
    final words = _normalize(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return books;
    return books.where((book) {
      final haystack =
          _normalize('${book.title} ${book.author} ${book.publisher} '
              '${book.series} ${book.tags} ${book.description}');
      return words.every(haystack.contains);
    }).toList();
  }

  static String _normalize(String s) => removeDiacritics(s).toLowerCase();

  /// [error] is replaced only when [error] or [clearError] is given.
  BookState copyWith({
    List<Book>? books,
    String? query,
    String? libraryRoot,
    LibraryLoadError? error,
    bool clearError = false,
    bool? loaded,
  }) {
    return BookState(
      books: books ?? this.books,
      query: query ?? this.query,
      libraryRoot: libraryRoot ?? this.libraryRoot,
      error: clearError ? null : (error ?? this.error),
      loaded: loaded ?? this.loaded,
    );
  }

  BookState update({
    List<Book>? books,
    String? query,
  }) {
    return copyWith(books: books, query: query);
  }

  @override
  List<Object?> get props => [books, query, libraryRoot, error, loaded];
}
