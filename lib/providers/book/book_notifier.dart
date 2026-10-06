import 'dart:io' show File, FileSystemException, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import '../../data/data_export.dart';
import '../../data/datasource/book_datasource_provider.dart';
import '../../metadata/metadata.dart';
import '../../utils/file_service.dart';
import '../../utils/storage_permission.dart';
import '../path_provider.dart';
import 'book_export.dart';
import 'book_search.dart';

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

  /// Search index being built / built for [_searchBooks] (see [search]).
  Future<BookSearch>? _searchIndex;
  List<Book>? _searchBooks;

  /// Bumped on every search, so an older search can't overwrite a newer one.
  int _searchSeq = 0;

  @override
  BookState build() {
    // Subscribe: folder change -> datasource/repository rebuilt -> this
    // rebuilds with a fresh, empty state (search query reset too).
    ref.watch(bookRepositoryProvider);
    _customPath = ref.watch(pathProvider);
    _generation++;
    _searchIndex = null;
    _searchBooks = null;
    _searchSeq++;
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

  /// Adds the file at [sourcePath] to the library the way Calibre does:
  /// the book row is created from [metadata] first, then the file is copied
  /// to `<Author>/<Title> (<id>)/<Title> - <Author>.<ext>` and the cover
  /// saved next to it as cover.jpg.
  ///
  /// Returns the new book id. Throws if anything fails - in that case the
  /// half-added book (row and folder) is removed again.
  Future<int> importFile(String sourcePath, BookMetadata metadata) async {
    final customPath = _customPath.isEmpty ? null : _customPath;
    final files = FileService();
    final extension =
        p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final title =
        metadata.title.trim().isEmpty ? Calibre.unknown : metadata.title.trim();
    final authors =
        metadata.authors.isEmpty ? const [Calibre.unknown] : metadata.authors;

    var book = Book(
      title: title,
      author: authors.join(' & '),
      price: '',
      image: '',
      path: '',
      filename: '',
      format: extension.toUpperCase(),
      last_modified: Calibre.now(),
      description: metadata.description,
      rating: (metadata.rating ?? 0).toDouble(),
      pages: metadata.pageCount ?? 0,
      publisher: metadata.publisher,
      series: metadata.series,
      series_index: metadata.seriesIndex ?? 1.0,
      tags: metadata.tags.join(', '),
      pubdate: metadata.pubdate == null
          ? ''
          : Calibre.formatTimestamp(metadata.pubdate!),
      languages: metadata.languages.join(', '),
      identifiers: Book.joinIdentifiers(metadata.identifiers),
    );

    // 1) The row first: Calibre's folder name contains the book id.
    final id = await _repository.addBook(book);
    if (id == null) throw StateError('The book could not be saved');
    book = book.copyWith(
      id: id,
      path: Calibre.bookFolder(id, title, authors.first),
      filename: Calibre.bookFileName(title, authors.first, extension),
    );

    try {
      // 2) The files.
      final target = await files.bookFilePath(
        path: book.path,
        filename: book.filename,
        format: extension,
        customPath: customPath,
      );
      await files.copyFile(oldpath: sourcePath, newpath: target);
      final cover = metadata.cover;
      if (cover != null) {
        await File(p.join(p.dirname(target), FileService.coverFileName))
            .writeAsBytes(cover, flush: true);
      }
      // 3) Path, file name, size and has_cover into the database.
      await _repository.updateBook(book);
    } catch (e) {
      try {
        await _repository.deleteBook(book);
        await files.deleteBookFolder(book.path, customPath: customPath);
      } catch (cleanupError) {
        debugPrint('Cleanup after failed import: $cleanupError');
      }
      rethrow;
    }

    await getBooks();
    return id;
  }

  /// Adds the file at [sourcePath] to [book] as another format (the way
  /// Calibre adds a format to an existing record): copied into the book's
  /// folder as `<book file name>.<ext>` plus a new `data` row. Throws if the
  /// book already has that format / file, or if anything fails (a copied
  /// file is removed again).
  Future<void> addFormat(Book book, String sourcePath) async {
    final id = book.id;
    if (id == null || book.path.isEmpty || book.filename.isEmpty) {
      throw StateError('The book has no folder in the library');
    }
    final extension =
        p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    if (extension.isEmpty) throw StateError('The file has no extension');
    final customPath = _customPath.isEmpty ? null : _customPath;
    final target = await FileService().bookFilePath(
      path: book.path,
      filename: book.filename,
      format: extension,
      customPath: customPath,
    );
    if (await File(target).exists()) {
      throw FileSystemException('The file already exists', target);
    }
    await FileService().copyFile(oldpath: sourcePath, newpath: target);
    try {
      await _repository.addFormat(
          id, extension.toUpperCase(), book.filename, await File(target).length());
    } catch (e) {
      try {
        await File(target).delete();
      } catch (cleanupError) {
        debugPrint('Cleanup after failed addFormat: $cleanupError');
      }
      rethrow;
    }
    await getBooks();
  }

  /// Books already in the library that look like the same book as
  /// [metadata]: same title (case and accents ignored) and at least one
  /// common author - or no real author on either side.
  List<Book> findDuplicates(BookMetadata metadata) {
    final title = _normalize(metadata.title);
    if (title.isEmpty) return const [];
    final authors = {
      for (final a in metadata.authors)
        if (!_isUnknownAuthor(a)) _normalize(a)
    };
    return [
      for (final book in state.books)
        if (_normalize(book.title) == title &&
            _authorsMatch(authors, book.author))
          book
    ];
  }

  static bool _authorsMatch(Set<String> authors, String bookAuthor) {
    final other = {
      for (final a in bookAuthor.split('&'))
        if (!_isUnknownAuthor(a)) _normalize(a)
    };
    if (authors.isEmpty || other.isEmpty) return true;
    return authors.any(other.contains);
  }

  static bool _isUnknownAuthor(String author) {
    final a = author.trim().toLowerCase();
    return a.isEmpty || a == Calibre.unknown.toLowerCase() || a == 'unknown author';
  }

  static String _normalize(String text) =>
      removeDiacritics(text).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> deleteBook(Book book) async {
    try {
      await _repository.deleteBook(book);
      getBooks();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Saves [book]. Throws if the database could not be updated, so the
  /// caller can undo file moves.
  Future<void> updateBook(Book book) async {
    await _repository.updateBook(book);
    getBooks();
  }

  Future<void> getBooks() async {
    final generation = _generation;
    final datasource = ref.read(bookDatasourceProvider);
    String? root;
    try {
      root = await FileService()
          .libraryRoot(customPath: _customPath.isEmpty ? null : _customPath);
      // A folder outside the app's own storage needs "All files access" on
      // Android 11+ (storage permission below). Without it sqlite can't open
      // metadata.db, so say so instead of showing an empty library.
      if (Platform.isAndroid &&
          _customPath.isNotEmpty &&
          !await StoragePermission.isGranted) {
        if (generation != _generation) return;
        state = state.copyWith(
          books: const [],
          libraryRoot: root,
          error: const LibraryLoadError.storagePermission(),
          loaded: true,
        );
        return;
      }
      // metadata.db exists but is damaged: don't open it (that would only
      // throw, or "repair" it into an empty library) - HomePage offers to
      // rebuild it from the metadata.opf files.
      if (await datasource.isDamaged()) {
        if (generation != _generation) return;
        state = state.copyWith(
          books: const [],
          libraryRoot: root,
          error: const LibraryLoadError.failed('metadata.db is damaged',
              damagedDatabase: true),
          loaded: true,
        );
        return;
      }
      final books = await _repository.getAllBooks();
      if (generation != _generation) return; // library changed meanwhile
      if (root != state.libraryRoot) {
        // Different library: drop decoded covers of the old one so nothing
        // stale (or a failed load) is reused from Flutter's image cache.
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
      }
      state = state.copyWith(
          books: books, libraryRoot: root, clearError: true, loaded: true);
      _booksChanged();
    } catch (e) {
      debugPrint('Library not loaded: $e');
      if (generation != _generation) return;
      // metadata.db exists but can't be opened -> HomePage offers to
      // rebuild it from the metadata.opf files.
      var damaged = false;
      try {
        damaged = await datasource.isDatabaseDamaged(e);
      } catch (checkError) {
        debugPrint('Database check failed: $checkError');
      }
      if (generation != _generation) return;
      state = state.copyWith(
        books: const [],
        libraryRoot: root,
        error: LibraryLoadError.failed('$e', damagedDatabase: damaged),
        loaded: true,
      );
    }
  }

  /// Rebuilds the damaged metadata.db of the current library from the
  /// metadata.opf files in the book folders (see
  /// [BookDatasource.restoreFromOpf]) and loads the library again.
  /// Throws if the rebuild failed (the old database is kept then).
  Future<LibraryRestoreResult> rebuildFromOpf(
      {void Function(int done, int total)? onProgress}) async {
    final datasource = ref.read(bookDatasourceProvider);
    try {
      return await datasource.restoreFromOpf(onProgress: onProgress);
    } finally {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await getBooks();
    }
  }

  /// Asks for storage access (Android) and loads the library again.
  Future<StorageAccess> grantAccessAndReload() async {
    final access = await StoragePermission.ensure();
    await getBooks();
    return access;
  }

  /// Search index for [books], reusing the one already built / being built.
  Future<BookSearch> _indexFor(List<Book> books) {
    final pending = _searchIndex;
    if (pending != null && identical(_searchBooks, books)) return pending;
    _searchBooks = books;
    final future = BookSearch.build(books);
    _searchIndex = future;
    // A failed build must not be reused.
    future.then((_) {}, onError: (Object e) {
      if (identical(_searchIndex, future)) {
        _searchIndex = null;
        _searchBooks = null;
      }
    });
    return future;
  }

  /// Called whenever [BookState.books] was replaced: prepares the search
  /// index in the background (so the next search is quick) and re-runs an
  /// active search on the new list.
  void _booksChanged() {
    if (state.query.isNotEmpty) {
      search(state.query);
    } else if (state.books.isNotEmpty) {
      _indexFor(state.books).then((_) {}, onError: (_) {});
    }
  }

  /// Filters the visible books (see [BookState.visibleBooks]). While it runs
  /// [BookState.searching] is true.
  Future<void> search(String query) async {
    final q = query.trim();
    final seq = ++_searchSeq;
    if (BookSearch.queryWords(q).isEmpty) {
      state = state.copyWith(query: q, clearFilter: true, searching: false);
      return;
    }
    state = state.copyWith(query: q, searching: true);
    try {
      final books = state.books;
      final index = await _indexFor(books);
      if (seq != _searchSeq) return; // a newer search / library took over
      state = state.copyWith(filteredBooks: index.filter(q), searching: false);
      if (!identical(books, state.books)) search(q); // books changed meanwhile
    } catch (e) {
      debugPrint('Search failed: $e');
      if (seq == _searchSeq) state = state.copyWith(searching: false);
    }
  }

  /// Shows every book again.
  void clearSearch() {
    _searchSeq++;
    state = state.copyWith(query: '', clearFilter: true, searching: false);
  }

  Future<Book?> getBook(int bookId) async {
    Book? book;
    try {
      final books = await _repository.getAllBooks();
      state = state.copyWith(books: books);
      _booksChanged();
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
      _booksChanged();
      return await _repository.getBookAuthorsByTitle(title);
    } catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }
}
