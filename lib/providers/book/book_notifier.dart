import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/data_export.dart';
import 'book_export.dart';

class BookNotifier extends Notifier<BookState> {
  late final BookRepository _repository;

  @override
  BookState build() {
    _repository = ref.watch(bookRepositoryProvider);
    getBooks();
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

  void getBooks() async {
    try {
      final books = await _repository.getAllBooks();
      state = state.copyWith(books: books);
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
