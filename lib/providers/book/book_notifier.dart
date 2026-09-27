import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/data_export.dart';
import '../../utils/file_service.dart';
import '../path_provider.dart';
import 'book_export.dart';

class BookNotifier extends Notifier<BookState> {
  /// Always the repository of the CURRENT library folder. (Not a
  /// `late final` field: Riverpod re-runs build() on the same notifier
  /// instance when the folder changes, and a late final can't be reassigned.)
  BookRepository get _repository => ref.read(bookRepositoryProvider);

  /// Bumped on every rebuild, so results of a load that started against
  /// the previous library are dropped instead of overwriting the new state.
  int _generation = 0;

  /// Custom library path this build belongs to ('' = default folder).
  String _customPath = '';

  @override
  BookState build() {
    // Subscribe: folder change -> datasource/repository rebuilt -> this
    // rebuilds with a fresh, empty state (search query reset too).
    ref.watch(bookRepositoryProvider);
    _customPath = ref.watch(pathProvider);
    _generation++;
    Future.microtask(getBooks);
    return const BookState.initial();
  }

  Future<int?> addBook(Book book) async {
    int? bookId;
    try {
      bookId = await _repository.addBook(book);
      getBooks();
    } catch (e) {
      debugPrint(e.toString());
    }
    return bookId;
  }

  Future<void> deleteBook(Book book) async {
    try {
      await _repository.deleteBook(book);
      getBooks();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> updateBook(Book book) async {
    try {
      final updatedBook = book.copyWith();
      await _repository.updateBook(updatedBook);
      getBooks();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> getBooks() async {
    final generation = _generation;
    try {
      final root = await FileService()
          .libraryRoot(customPath: _customPath.isEmpty ? null : _customPath);
      final books = await _repository.getAllBooks();
      if (generation != _generation) return; // library changed meanwhile
      if (root != state.libraryRoot) {
        // Different library: drop decoded covers of the old one so nothing
        // stale (or a failed load) is reused from Flutter's image cache.
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
      }
      state = state.copyWith(books: books, libraryRoot: root);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Filters the visible books (see [BookState.visibleBooks]).
  void search(String query) {
    state = state.copyWith(query: query.trim());
  }

  /// Shows every book again.
  void clearSearch() {
    state = state.copyWith(query: '');
  }

  Future<Book?> getBook(int bookId) async {
    Book? book;
    try {
      final books = await _repository.getAllBooks();
      state = state.copyWith(books: books);
      book = await _repository.getBook(bookId);
    } catch (e) {
      debugPrint(e.toString());
    }
    return book;
  }

  Future<String?> getTitlesByTitle(String title) async {
    try {
      final books = await _repository.getAllBooks();
      state = state.copyWith(books: books);
      return await _repository.getBookAuthorsByTitle(title);
    } catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }
}
