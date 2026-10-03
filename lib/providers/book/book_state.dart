import 'package:equatable/equatable.dart';
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

  /// Books matching [query], computed by `BookNotifier.search` (null = no
  /// filter, show every book).
  final List<Book>? filteredBooks;

  /// True while a search is running (progress bar under the search field).
  final bool searching;

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
    this.filteredBooks,
    this.searching = false,
    this.libraryRoot,
    this.error,
    this.loaded = false,
  });
  const BookState.initial({
    this.books = const [],
    this.query = '',
    this.filteredBooks,
    this.searching = false,
    this.libraryRoot,
    this.error,
    this.loaded = false,
  });

  /// The books to show: all of them, or the search result.
  List<Book> get visibleBooks => filteredBooks ?? books;

  /// [error] is replaced only when [error] or [clearError] is given;
  /// [filteredBooks] only when it is given or [clearFilter] is set.
  ///
  /// New [books] while a filter is active (e.g. after editing a book) keep
  /// the same books visible, by id, until the search is re-run.
  BookState copyWith({
    List<Book>? books,
    String? query,
    List<Book>? filteredBooks,
    bool clearFilter = false,
    bool? searching,
    String? libraryRoot,
    LibraryLoadError? error,
    bool clearError = false,
    bool? loaded,
  }) {
    final newBooks = books ?? this.books;
    var filtered = clearFilter ? null : (filteredBooks ?? this.filteredBooks);
    if (filteredBooks == null &&
        filtered != null &&
        !identical(newBooks, this.books)) {
      final ids = {for (final b in filtered) b.id};
      filtered = newBooks.where((b) => ids.contains(b.id)).toList();
    }
    return BookState(
      books: newBooks,
      query: query ?? this.query,
      filteredBooks: filtered,
      searching: searching ?? this.searching,
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

  /// Short form for logs (MyObserver prints every state change). Equatable's
  /// default would print every book of the library - with thousands of
  /// books that froze the UI on each update in debug mode.
  @override
  String toString() => 'BookState(books: ${books.length}, '
      'query: "$query", filtered: ${filteredBooks?.length}, '
      'searching: $searching, loaded: $loaded, error: $error, '
      'libraryRoot: $libraryRoot)';

  @override
  List<Object?> get props =>
      [books, query, filteredBooks, searching, libraryRoot, error, loaded];
}
