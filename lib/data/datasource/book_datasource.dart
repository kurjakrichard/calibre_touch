// ignore: depend_on_referenced_packages
import 'dart:io' show Directory, File, Platform, Process;
import 'dart:math';
import 'package:path/path.dart' show dirname, join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../utils/utils.dart';
import '../models/book.dart';

/// Calibre's schema version for the schema created in [_onCreate]
/// (matches `pragma user_version` at the end of Calibre's
/// resources/metadata_sqlite.sql for a schema that has
/// books_pages_link but not yet book_storage).
///
/// sqflite writes the `version` passed to openDatabase into
/// `PRAGMA user_version`. Calibre reads that same pragma to decide which
/// schema upgrades to run, so it MUST be Calibre's version and not 1 -
/// otherwise Calibre replays upgrade_version_1, _2, ... on a database
/// that already has everything and fails with
/// "trigger fkc_delete_on_authors already exists".
const int calibreSchemaVersion = 27;

/// Sqlite-backed datasource for [Book].
///
/// The schema created in [_onCreate] is the real Calibre-style
/// "recreate_schema.sql" schema (authors, books, publishers, series,
/// tags, ratings, languages, identifiers, data, comments, plus all the
/// books_*_link join tables, indexes, views and triggers) - not the old
/// single flat `books` table. [Book] itself is unchanged: every method
/// below still takes/returns a plain [Book], it just now reads and
/// writes it across the normalized tables underneath:
///   - Book.author   <-> authors + books_authors_link ('&'-separated,
///                       so "Jane Doe & John Smith" becomes two rows)
///   - Book.rating   <-> ratings + books_ratings_link (schema stores
///                       an INTEGER 0-10, Book stores a double - rounded
///                       on write, cast back to REAL on read)
///   - Book.description <-> comments.text
///   - Book.pages    <-> books_pages_link.pages (a real column in the
///                       Calibre schema, auto-created per book by
///                       books_pages_link_create_trigger)
///   - Book.filename/format <-> data.name / data.format (first/only
///                       data row for that book)
///   - Book.price / Book.image  - there's no Calibre column for either
///                       of these app-specific fields, so they're kept
///                       as ordinary rows in `identifiers`
///                       (type='price' / type='cover_image'). That
///                       table is exactly Calibre's own extension point
///                       for "an arbitrary string tied to a book", so
///                       this needs no schema changes.
///   - Book.id/title/path/last_modified <-> books columns directly.
///
/// `sort`, `author_sort` and `uuid` (real columns on `books`) are
/// computed here in Dart and are not exposed on [Book].
///
/// IMPORTANT - title_sort()/uuid4(): the schema's `books_insert_trg`,
/// `books_update_trg`, `series_insert_trg` and `series_update_trg`
/// call these as custom SQL functions the way Calibre's own Python
/// host provides them. Plain sqlite3 doesn't have them. CREATE TRIGGER
/// still succeeds (SQLite only parses a trigger body as text at
/// creation time), but the trigger must never be allowed to actually
/// fire - so every write to `books` here drops `books_insert_trg` /
/// `books_update_trg` first via [DropTriggers], and recreates it via
/// [Triggers] afterwards, computing `sort`/`uuid` itself in the
/// meantime with [_titleSort]/[_newUuid] below.
class BookDatasource {
  /// The user's custom library path, as held by `pathProvider`. Never read
  /// from SharedPreferences directly here - `bookDatasourceProvider` is the
  /// only place that resolves it, from `pathProvider`, and hands it in.
  ///
  /// One instance = one library. When the folder changes, the provider
  /// builds a NEW instance and calls [close] on the old one, so there is
  /// deliberately no static/singleton state in this class.
  final String? _customPath;

  /// Memoized open: concurrent callers share the same open instead of
  /// racing to open metadata.db twice.
  Future<Database>? _dbFuture;
  bool _closed = false;

  BookDatasource({String? customPath}) : _customPath = customPath;

  Future<Database> get database {
    if (_closed) {
      return Future.error(StateError('BookDatasource for "$_customPath" was closed'));
    }
    return _dbFuture ??= _open();
  }

  Future<Database> _open() async {
    final libraryDir = await FileService().libraryRoot(customPath: _customPath);
    // sqlite can't create metadata.db inside a folder that doesn't exist yet
    // (e.g. the default <documents>/ebooks on first run).
    await Directory(libraryDir).create(recursive: true);
    final path = join(libraryDir, dbName);

    final Database database;
    if (Platform.isAndroid || Platform.isIOS) {
      database = await openDatabase(
        path,
        version: calibreSchemaVersion,
        onUpgrade: _onUpgrade,
        onCreate: _onCreate,
      );
    } else {
      sqfliteFfiInit();
      database = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: calibreSchemaVersion,
          onUpgrade: _onUpgrade,
          onCreate: _onCreate,
        ),
      );
    }
    await database.execute('PRAGMA foreign_keys = ON');
    return database;
  }

  // ---- Dart-side replacements for Calibre's title_sort()/uuid4() ----

  /// Mimics Calibre's title_sort(): move a single leading "A"/"An"/"The"
  /// to the end after a comma, so titles sort by their real first word.
  String _titleSort(String title) {
    final t = title.trim();
    final match = RegExp(r'^(A|An|The)\s+(.+)$', caseSensitive: false)
        .firstMatch(t);
    if (match == null) return t;
    return '${match.group(2)}, ${match.group(1)}';
  }

  String _newUuid() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  List<String> _splitAuthors(String author) => author
      .split('&')
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();

  /// Look up a taxonomy row (authors/ratings/...) by its unique text
  /// field and return its id, inserting [ifMissing] first if no row
  /// matches yet.
  Future<int> _getOrCreateId(
    DatabaseExecutor db,
    String table,
    String field,
    String searchItem,
    Map<String, dynamic> ifMissing,
  ) async {
    final rows = await db
        .query(table, where: '$field = ?', whereArgs: [searchItem], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return db.insert(table, ifMissing,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Insert a row into a books_*_link join table, ignoring the insert
  /// if that (book, target) pair is already linked (every link table
  /// in the schema has a UNIQUE(book, ...) constraint).
  Future<void> _linkBook(
    DatabaseExecutor db,
    String linkTable,
    int bookId,
    String targetColumn,
    int targetId,
  ) async {
    await db.insert(
      linkTable,
      {'book': bookId, targetColumn: targetId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Shared SELECT list used by [getBook]/[getAllBooks], expressed with
  /// the same keys [Book.fromJson] reads via [Bookkeys] - every
  /// nullable sub-select is COALESCEd so Book's non-nullable fields
  /// never receive a null.
  String get _bookSelect => '''
    SELECT
      books.id AS ${Bookkeys.id.name},
      books.title AS ${Bookkeys.title.name},
      COALESCE((SELECT group_concat(name, ' & ') FROM books_authors_link bal
                JOIN authors ON authors.id = bal.author
                WHERE bal.book = books.id), '') AS ${Bookkeys.author.name},
      COALESCE((SELECT val FROM identifiers
                WHERE identifiers.book = books.id AND type = 'price'), '')
          AS ${Bookkeys.price.name},
      COALESCE((SELECT val FROM identifiers
                WHERE identifiers.book = books.id AND type = 'cover_image'), '')
          AS ${Bookkeys.image.name},
      books.path AS ${Bookkeys.path.name},
      COALESCE((SELECT name FROM data WHERE data.book = books.id LIMIT 1), '')
          AS ${Bookkeys.filename.name},
      COALESCE((SELECT format FROM data WHERE data.book = books.id LIMIT 1), '')
          AS ${Bookkeys.format.name},
      books.last_modified AS ${Bookkeys.last_modified.name},
      COALESCE((SELECT text FROM comments WHERE comments.book = books.id), '')
          AS ${Bookkeys.description.name},
      COALESCE((SELECT pages FROM books_pages_link
                WHERE books_pages_link.book = books.id), 0)
          AS ${Bookkeys.pages.name},
      COALESCE((SELECT CAST(rating AS REAL) FROM ratings
                WHERE ratings.id IN
                  (SELECT rating FROM books_ratings_link WHERE book = books.id)),
               0.0) AS ${Bookkeys.rating.name}
    FROM books
  ''';

  /// Calibre's `books.has_cover` must match whether cover.jpg really exists
  /// in the book's folder (the library folder is the one holding the db).
  bool _hasCover(Database db, Book book) {
    if (book.path.isEmpty) return false;
    return File(FileService.coverPathIn(dirname(db.path), book.path))
        .existsSync();
  }

  Future<int> addBook(Book book) async {
    final db = await database;
    final sort = _titleSort(book.title);
    final authors = _splitAuthors(book.author);
    final authorSort = authors.join(' & ');
    final uuid = _newUuid();

    return db.transaction<int>((txn) async {
      // books_insert_trg calls title_sort()/uuid4() - neither exists in
      // plain sqlite, so drop it for this insert (sort/uuid are already
      // computed above) and restore it straight after.
      await txn.execute(DropTriggers.books_insert_trg_drop.name);
      late final int bookId;
      try {
        bookId = await txn.insert('books', {
          if (book.id != null) 'id': book.id,
          'title': book.title,
          'sort': sort,
          'author_sort': authorSort,
          'path': book.path,
          'uuid': uuid,
          'has_cover': _hasCover(db, book) ? 1 : 0,
          'last_modified': book.last_modified,
        });
      } finally {
        await txn.execute(Triggers.books_insert_trg.name);
      }

      await txn.insert(
        'data',
        {
          'book': bookId,
          'format': book.format,
          'uncompressed_size': 0,
          'name': book.filename,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (book.description.trim().isNotEmpty) {
        await txn.insert(
          'comments',
          {'book': bookId, 'text': HtmlText.toHtml(book.description)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // books_pages_link_create_trigger already created a pages=0 row.
      await txn.update('books_pages_link', {'pages': book.pages},
          where: 'book = ?', whereArgs: [bookId]);

      for (final name in authors) {
        final authorId = await _getOrCreateId(
            txn, 'authors', 'name', name, {'name': name, 'sort': name, 'link': ''});
        await _linkBook(txn, 'books_authors_link', bookId, 'author', authorId);
      }

      if (book.rating > 0) {
        final ratingValue = book.rating.round().clamp(0, 10);
        final ratingId = await _getOrCreateId(txn, 'ratings', 'rating',
            ratingValue.toString(), {'rating': ratingValue, 'link': ''});
        await _linkBook(
            txn, 'books_ratings_link', bookId, 'rating', ratingId);
      }

      if (book.price.isNotEmpty) {
        await txn.insert(
          'identifiers',
          {'book': bookId, 'type': 'price', 'val': book.price},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (book.image.isNotEmpty) {
        await txn.insert(
          'identifiers',
          {'book': bookId, 'type': 'cover_image', 'val': book.image},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return bookId;
    });
  }

  Future<Book?> getBook(int id) async {
    final db = await database;
    final map = await db.rawQuery('$_bookSelect WHERE books.id = ?', [id]);
    if (map.isEmpty) return null;
    return Book.fromJson(map.first);
  }

  Future<String?> getBookAuthorsByTitle(String title) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT group_concat(name, ' & ') AS authors
      FROM books_authors_link bal
      JOIN authors ON authors.id = bal.author
      JOIN books ON books.id = bal.book
      WHERE books.title = ?
      GROUP BY bal.book
    ''', [title]);

    if (rows.isEmpty) return null;
    final bookAuthors = rows.map((r) => r['authors'] as String? ?? '').toList();
    return bookAuthors.toString();
  }

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final maps = await db.rawQuery('$_bookSelect ORDER BY books.id DESC');
    return List.generate(maps.length, (index) => Book.fromJson(maps[index]));
  }

  Future<int> updateBook(Book book) async {
    final db = await database;
    if (book.id == null) return 0;
    final bookId = book.id!;
    final sort = _titleSort(book.title);
    final authors = _splitAuthors(book.author);
    final authorSort = authors.join(' & ');

    return db.transaction<int>((txn) async {
      // books_update_trg also calls title_sort() - same drop/recreate
      // dance as addBook, for the same reason.
      await txn.execute(DropTriggers.books_books_update_trg_drop.name);
      int result;
      try {
        result = await txn.update(
          'books',
          {
            'title': book.title,
            'sort': sort,
            'author_sort': authorSort,
            'path': book.path,
            'has_cover': _hasCover(db, book) ? 1 : 0,
            'last_modified': book.last_modified,
          },
          where: 'id = ?',
          whereArgs: [bookId],
        );
      } finally {
        await txn.execute(Triggers.books_update_trg.name);
      }

      await txn.update(
        'data',
        {'format': book.format, 'name': book.filename},
        where: 'book = ?',
        whereArgs: [bookId],
      );
      if (await txn.query('data', where: 'book = ?', whereArgs: [bookId])
          .then((rows) => rows.isEmpty)) {
        await txn.insert('data', {
          'book': bookId,
          'format': book.format,
          'uncompressed_size': 0,
          'name': book.filename,
        });
      }

      // Calibre expects comments.text to be HTML.
      if (book.description.trim().isEmpty) {
        await txn.delete('comments', where: 'book = ?', whereArgs: [bookId]);
      } else {
        await txn.insert(
          'comments',
          {'book': bookId, 'text': HtmlText.toHtml(book.description)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.update('books_pages_link', {'pages': book.pages},
          where: 'book = ?', whereArgs: [bookId]);

      // Authors can change on update - replace the link set entirely.
      await txn.delete('books_authors_link',
          where: 'book = ?', whereArgs: [bookId]);
      for (final name in authors) {
        final authorId = await _getOrCreateId(
            txn, 'authors', 'name', name, {'name': name, 'sort': name, 'link': ''});
        await _linkBook(txn, 'books_authors_link', bookId, 'author', authorId);
      }

      await txn.delete('books_ratings_link',
          where: 'book = ?', whereArgs: [bookId]);
      if (book.rating > 0) {
        final ratingValue = book.rating.round().clamp(0, 10);
        final ratingId = await _getOrCreateId(txn, 'ratings', 'rating',
            ratingValue.toString(), {'rating': ratingValue, 'link': ''});
        await _linkBook(
            txn, 'books_ratings_link', bookId, 'rating', ratingId);
      }

      await txn.insert(
        'identifiers',
        {'book': bookId, 'type': 'price', 'val': book.price},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'identifiers',
        {'book': bookId, 'type': 'cover_image', 'val': book.image},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return result;
    });
  }

  Future<int> deleteBook(Book book) async {
    final db = await database;
    // books_delete_trg (AFTER DELETE ON books) already cascades cleanup
    // of every books_*_link row, data, comments and identifiers for
    // this book. books_pages_link has an explicit
    // ON DELETE CASCADE foreign key instead, honoured because
    // PRAGMA foreign_keys was turned on when the database was opened.
    return db.delete('books', where: 'id = ?', whereArgs: [book.id]);
  }

  /// Closes this library's database (called by the provider's onDispose
  /// when the library folder changes). Safe to call more than once, and a
  /// no-op if the database was never opened.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pending = _dbFuture;
    _dbFuture = null;
    if (pending == null) return;
    try {
      final db = await pending;
      await db.close();
    } catch (_) {
      // Open failed - nothing to close.
    }
  }

  // This creates tables in our database - the full schema from
  // recreate_schema.sql (see the class doc comment above for the
  // title_sort()/uuid4() caveat).
  // Databases created by older builds of this app were stamped with
  // user_version=1 (or 2, if Calibre already tried upgrading them). The
  // schema itself is already current, so nothing to migrate - sqflite
  // re-stamps user_version with [calibreSchemaVersion] after this runs.
  // Those libraries also never got .calnotes/.caltrash, so add them here.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _createLibraryFolders(dirname(db.path));
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE authors ( id   INTEGER PRIMARY KEY,
                              name TEXT NOT NULL COLLATE NOCASE,
                              sort TEXT COLLATE NOCASE,
                              link TEXT NOT NULL DEFAULT '',
                              UNIQUE(name)
                             );
CREATE TABLE books ( id      INTEGER PRIMARY KEY AUTOINCREMENT,
                             title     TEXT NOT NULL DEFAULT 'Unknown' COLLATE NOCASE,
                             sort      TEXT COLLATE NOCASE,
                             timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             pubdate   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             series_index REAL NOT NULL DEFAULT 1.0,
                             author_sort TEXT COLLATE NOCASE,
                             path TEXT NOT NULL DEFAULT '',
                             uuid TEXT,
                             has_cover BOOL DEFAULT 0,
                             last_modified TIMESTAMP NOT NULL DEFAULT '2000-01-01 00:00:00+00:00');
CREATE TABLE books_authors_link ( id INTEGER PRIMARY KEY,
                                          book INTEGER NOT NULL,
                                          author INTEGER NOT NULL,
                                          UNIQUE(book, author)
                                        );
CREATE TABLE books_languages_link ( id INTEGER PRIMARY KEY,
                                            book INTEGER NOT NULL,
                                            lang_code INTEGER NOT NULL,
                                            item_order INTEGER NOT NULL DEFAULT 0,
                                            UNIQUE(book, lang_code)
        );
CREATE TABLE books_plugin_data(id INTEGER PRIMARY KEY,
                                     book INTEGER NOT NULL,
                                     name TEXT NOT NULL,
                                     val TEXT NOT NULL,
                                     UNIQUE(book,name));
CREATE TABLE books_publishers_link ( id INTEGER PRIMARY KEY,
                                          book INTEGER NOT NULL,
                                          publisher INTEGER NOT NULL,
                                          UNIQUE(book)
                                        );
CREATE TABLE books_ratings_link ( id INTEGER PRIMARY KEY,
                                          book INTEGER NOT NULL,
                                          rating INTEGER NOT NULL,
                                          UNIQUE(book, rating)
                                        );
CREATE TABLE books_series_link ( id INTEGER PRIMARY KEY,
                                          book INTEGER NOT NULL,
                                          series INTEGER NOT NULL,
                                          UNIQUE(book)
                                        );
CREATE TABLE books_pages_link (
    book INTEGER PRIMARY KEY,
    pages INTEGER DEFAULT 0 NOT NULL,
    algorithm INTEGER DEFAULT 0 NOT NULL,
    format TEXT DEFAULT '' NOT NULL COLLATE NOCASE,
    format_size INTEGER DEFAULT 0 NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    needs_scan INTEGER NOT NULL DEFAULT 0 CHECK(needs_scan IN (0, 1)),
    FOREIGN KEY (book) REFERENCES books(id) ON DELETE CASCADE
);
CREATE TABLE books_tags_link ( id INTEGER PRIMARY KEY,
                                          book INTEGER NOT NULL,
                                          tag INTEGER NOT NULL,
                                          UNIQUE(book, tag)
                                        );
CREATE TABLE comments ( id INTEGER PRIMARY KEY,
                              book INTEGER NOT NULL,
                              text TEXT NOT NULL COLLATE NOCASE,
                              UNIQUE(book)
                            );
CREATE TABLE conversion_options ( id INTEGER PRIMARY KEY,
                                          format TEXT NOT NULL COLLATE NOCASE,
                                          book INTEGER,
                                          data BLOB NOT NULL,
                                          UNIQUE(format,book)
                                        );
CREATE TABLE custom_columns (
                    id       INTEGER PRIMARY KEY AUTOINCREMENT,
                    label    TEXT NOT NULL,
                    name     TEXT NOT NULL,
                    datatype TEXT NOT NULL,
                    mark_for_delete   BOOL DEFAULT 0 NOT NULL,
                    editable BOOL DEFAULT 1 NOT NULL,
                    display  TEXT DEFAULT '{}' NOT NULL,
                    is_multiple BOOL DEFAULT 0 NOT NULL,
                    normalized BOOL NOT NULL,
                    UNIQUE(label)
                );
CREATE TABLE data ( id     INTEGER PRIMARY KEY,
                            book   INTEGER NOT NULL,
                            format TEXT NOT NULL COLLATE NOCASE,
                            uncompressed_size INTEGER NOT NULL,
                            name TEXT NOT NULL,
                            UNIQUE(book, format)
);
CREATE TABLE feeds ( id   INTEGER PRIMARY KEY,
                              title TEXT NOT NULL,
                              script TEXT NOT NULL,
                              UNIQUE(title)
                             );
CREATE TABLE identifiers  ( id     INTEGER PRIMARY KEY,
                                    book   INTEGER NOT NULL,
                                    type   TEXT NOT NULL DEFAULT 'isbn' COLLATE NOCASE,
                                    val    TEXT NOT NULL COLLATE NOCASE,
                                    UNIQUE(book, type)
        );
CREATE TABLE languages    ( id        INTEGER PRIMARY KEY,
                                    lang_code TEXT NOT NULL COLLATE NOCASE,
							        link TEXT NOT NULL DEFAULT '',
                                    UNIQUE(lang_code)
        );
CREATE TABLE library_id ( id   INTEGER PRIMARY KEY,
                                  uuid TEXT NOT NULL,
                                  UNIQUE(uuid)
        );
CREATE TABLE metadata_dirtied(id INTEGER PRIMARY KEY,
                             book INTEGER NOT NULL,
                             UNIQUE(book));
CREATE TABLE annotations_dirtied(id INTEGER PRIMARY KEY,
                             book INTEGER NOT NULL,
                             UNIQUE(book));
CREATE TABLE preferences(id INTEGER PRIMARY KEY,
                                 key TEXT NOT NULL,
                                 val TEXT NOT NULL,
                                 UNIQUE(key));
CREATE TABLE publishers ( id   INTEGER PRIMARY KEY,
                                  name TEXT NOT NULL COLLATE NOCASE,
                                  sort TEXT COLLATE NOCASE,
								  link TEXT NOT NULL DEFAULT '',
                                  UNIQUE(name)
                             );
CREATE TABLE ratings ( id   INTEGER PRIMARY KEY,
                               rating INTEGER CHECK(rating > -1 AND rating < 11),
							   link TEXT NOT NULL DEFAULT '',
                               UNIQUE (rating)
                             );
CREATE TABLE series ( id   INTEGER PRIMARY KEY,
                              name TEXT NOT NULL COLLATE NOCASE,
                              sort TEXT COLLATE NOCASE,
							  link TEXT NOT NULL DEFAULT '',
                              UNIQUE (name)
                             );
CREATE TABLE tags ( id   INTEGER PRIMARY KEY,
                            name TEXT NOT NULL COLLATE NOCASE,
							link TEXT NOT NULL DEFAULT '',
                            UNIQUE (name)
                             );
CREATE TABLE last_read_positions ( id INTEGER PRIMARY KEY,
	book INTEGER NOT NULL,
	format TEXT NOT NULL COLLATE NOCASE,
	user TEXT NOT NULL,
	device TEXT NOT NULL,
	cfi TEXT NOT NULL,
	epoch REAL NOT NULL,
	pos_frac REAL NOT NULL DEFAULT 0,
	UNIQUE(user, device, book, format)
);
CREATE TABLE annotations ( id INTEGER PRIMARY KEY,
	book INTEGER NOT NULL,
	format TEXT NOT NULL COLLATE NOCASE,
	user_type TEXT NOT NULL,
	user TEXT NOT NULL,
	timestamp REAL NOT NULL,
	annot_id TEXT NOT NULL,
	annot_type TEXT NOT NULL,
	annot_data TEXT NOT NULL,
    searchable_text TEXT NOT NULL DEFAULT '',
    UNIQUE(book, user_type, user, format, annot_type, annot_id)
);
CREATE VIRTUAL TABLE annotations_fts USING fts5(searchable_text, content = 'annotations', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2');
CREATE VIRTUAL TABLE annotations_fts_stemmed USING fts5(searchable_text, content = 'annotations', content_rowid = 'id', tokenize = 'porter unicode61 remove_diacritics 2');
CREATE INDEX books_pages_link_pidx ON books_pages_link (needs_scan);
CREATE INDEX authors_idx ON books (author_sort COLLATE NOCASE);
CREATE INDEX books_authors_link_aidx ON books_authors_link (author);
CREATE INDEX books_authors_link_bidx ON books_authors_link (book);
CREATE INDEX books_idx ON books (sort COLLATE NOCASE);
CREATE INDEX books_languages_link_aidx ON books_languages_link (lang_code);
CREATE INDEX books_languages_link_bidx ON books_languages_link (book);
CREATE INDEX books_publishers_link_aidx ON books_publishers_link (publisher);
CREATE INDEX books_publishers_link_bidx ON books_publishers_link (book);
CREATE INDEX books_ratings_link_aidx ON books_ratings_link (rating);
CREATE INDEX books_ratings_link_bidx ON books_ratings_link (book);
CREATE INDEX books_series_link_aidx ON books_series_link (series);
CREATE INDEX books_series_link_bidx ON books_series_link (book);
CREATE INDEX books_tags_link_aidx ON books_tags_link (tag);
CREATE INDEX books_tags_link_bidx ON books_tags_link (book);
CREATE INDEX comments_idx ON comments (book);
CREATE INDEX conversion_options_idx_a ON conversion_options (format COLLATE NOCASE);
CREATE INDEX conversion_options_idx_b ON conversion_options (book);
CREATE INDEX custom_columns_idx ON custom_columns (label);
CREATE INDEX data_idx ON data (book);
CREATE INDEX lrp_idx ON last_read_positions (book);
CREATE INDEX annot_idx ON annotations (book);
CREATE INDEX formats_idx ON data (format);
CREATE INDEX languages_idx ON languages (lang_code COLLATE NOCASE);
CREATE INDEX publishers_idx ON publishers (name COLLATE NOCASE);
CREATE INDEX series_idx ON series (name COLLATE NOCASE);
CREATE INDEX tags_idx ON tags (name COLLATE NOCASE);
CREATE VIEW meta AS
        SELECT id, title,
               (SELECT sortconcat(bal.id, name) FROM books_authors_link AS bal JOIN authors ON(author = authors.id) WHERE book = books.id) authors,
               (SELECT name FROM publishers WHERE publishers.id IN (SELECT publisher from books_publishers_link WHERE book=books.id)) publisher,
               (SELECT rating FROM ratings WHERE ratings.id IN (SELECT rating from books_ratings_link WHERE book=books.id)) rating,
               timestamp,
               (SELECT MAX(uncompressed_size) FROM data WHERE book=books.id) size,
               (SELECT concat(name) FROM tags WHERE tags.id IN (SELECT tag from books_tags_link WHERE book=books.id)) tags,
               (SELECT text FROM comments WHERE book=books.id) comments,
               (SELECT name FROM series WHERE series.id IN (SELECT series FROM books_series_link WHERE book=books.id)) series,
               series_index,
               sort,
               author_sort,
               (SELECT concat(format) FROM data WHERE data.book=books.id) formats,
               path,
               pubdate,
               uuid
        FROM books;
CREATE VIEW tag_browser_authors AS SELECT
                    id,
                    name,
                    (SELECT COUNT(id) FROM books_authors_link WHERE author=authors.id) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_authors_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.author=authors.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
                     sort AS sort
                FROM authors;
CREATE VIEW tag_browser_filtered_authors AS SELECT
                    id,
                    name,
                    (SELECT COUNT(books_authors_link.id) FROM books_authors_link WHERE
                        author=authors.id AND books_list_filter(book)) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_authors_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.author=authors.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0 AND
                     books_list_filter(bl.book)) avg_rating,
                     sort AS sort
                FROM authors;
CREATE VIEW tag_browser_filtered_publishers AS SELECT
                    id,
                    name,
                    (SELECT COUNT(books_publishers_link.id) FROM books_publishers_link WHERE
                        publisher=publishers.id AND books_list_filter(book)) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_publishers_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.publisher=publishers.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0 AND
                     books_list_filter(bl.book)) avg_rating,
                     name AS sort
                FROM publishers;
CREATE VIEW tag_browser_filtered_ratings AS SELECT
                    id,
                    rating,
                    (SELECT COUNT(books_ratings_link.id) FROM books_ratings_link WHERE
                        rating=ratings.id AND books_list_filter(book)) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_ratings_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.rating=ratings.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0 AND
                     books_list_filter(bl.book)) avg_rating,
                     rating AS sort
                FROM ratings;
CREATE VIEW tag_browser_filtered_series AS SELECT
                    id,
                    name,
                    (SELECT COUNT(books_series_link.id) FROM books_series_link WHERE
                        series=series.id AND books_list_filter(book)) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_series_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.series=series.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0 AND
                     books_list_filter(bl.book)) avg_rating,
                     (title_sort(name)) AS sort
                FROM series;
CREATE VIEW tag_browser_filtered_tags AS SELECT
                    id,
                    name,
                    (SELECT COUNT(books_tags_link.id) FROM books_tags_link WHERE
                        tag=tags.id AND books_list_filter(book)) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_tags_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.tag=tags.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0 AND
                     books_list_filter(bl.book)) avg_rating,
                     name AS sort
                FROM tags;
CREATE VIEW tag_browser_publishers AS SELECT
                    id,
                    name,
                    (SELECT COUNT(id) FROM books_publishers_link WHERE publisher=publishers.id) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_publishers_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.publisher=publishers.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
                     name AS sort
                FROM publishers;
CREATE VIEW tag_browser_ratings AS SELECT
                    id,
                    rating,
                    (SELECT COUNT(id) FROM books_ratings_link WHERE rating=ratings.id) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_ratings_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.rating=ratings.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
                     rating AS sort
                FROM ratings;
CREATE VIEW tag_browser_series AS SELECT
                    id,
                    name,
                    (SELECT COUNT(id) FROM books_series_link WHERE series=series.id) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_series_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.series=series.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
                     (title_sort(name)) AS sort
                FROM series;
CREATE VIEW tag_browser_tags AS SELECT
                    id,
                    name,
                    (SELECT COUNT(id) FROM books_tags_link WHERE tag=tags.id) count,
                    (SELECT AVG(ratings.rating)
                     FROM books_tags_link AS tl, books_ratings_link AS bl, ratings
                     WHERE tl.tag=tags.id AND bl.book=tl.book AND
                     ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
                     name AS sort
                FROM tags;
CREATE TRIGGER books_pages_link_create_trigger AFTER INSERT ON books FOR EACH ROW
BEGIN
    INSERT INTO books_pages_link(book) VALUES(NEW.id);
END;
CREATE TRIGGER annotations_fts_insert_trg AFTER INSERT ON annotations
BEGIN
    INSERT INTO annotations_fts(rowid, searchable_text) VALUES (NEW.id, NEW.searchable_text);
    INSERT INTO annotations_fts_stemmed(rowid, searchable_text) VALUES (NEW.id, NEW.searchable_text);
END;
CREATE TRIGGER annotations_fts_delete_trg AFTER DELETE ON annotations
BEGIN
    INSERT INTO annotations_fts(annotations_fts, rowid, searchable_text) VALUES('delete', OLD.id, OLD.searchable_text);
    INSERT INTO annotations_fts_stemmed(annotations_fts_stemmed, rowid, searchable_text) VALUES('delete', OLD.id, OLD.searchable_text);
END;
CREATE TRIGGER annotations_fts_update_trg AFTER UPDATE ON annotations
BEGIN
    INSERT INTO annotations_fts(annotations_fts, rowid, searchable_text) VALUES('delete', OLD.id, OLD.searchable_text);
    INSERT INTO annotations_fts(rowid, searchable_text) VALUES (NEW.id, NEW.searchable_text);
    INSERT INTO annotations_fts_stemmed(annotations_fts_stemmed, rowid, searchable_text) VALUES('delete', OLD.id, OLD.searchable_text);
    INSERT INTO annotations_fts_stemmed(rowid, searchable_text) VALUES (NEW.id, NEW.searchable_text);
END;
CREATE TRIGGER books_delete_trg
            AFTER DELETE ON books
            BEGIN
                DELETE FROM books_authors_link WHERE book=OLD.id;
                DELETE FROM books_publishers_link WHERE book=OLD.id;
                DELETE FROM books_ratings_link WHERE book=OLD.id;
                DELETE FROM books_series_link WHERE book=OLD.id;
                DELETE FROM books_tags_link WHERE book=OLD.id;
                DELETE FROM books_languages_link WHERE book=OLD.id;
                DELETE FROM data WHERE book=OLD.id;
                DELETE FROM last_read_positions WHERE book=OLD.id;
                DELETE FROM annotations WHERE book=OLD.id;
                DELETE FROM comments WHERE book=OLD.id;
                DELETE FROM conversion_options WHERE book=OLD.id;
                DELETE FROM books_plugin_data WHERE book=OLD.id;
                DELETE FROM identifiers WHERE book=OLD.id;
        END;
CREATE TRIGGER books_insert_trg AFTER INSERT ON books
        BEGIN
            UPDATE books SET sort=title_sort(NEW.title),uuid=uuid4() WHERE id=NEW.id;
        END;
CREATE TRIGGER books_update_trg
            AFTER UPDATE ON books
            BEGIN
            UPDATE books SET sort=title_sort(NEW.title)
                         WHERE id=NEW.id AND OLD.title <> NEW.title;
            END;
CREATE TRIGGER fkc_comments_insert
        BEFORE INSERT ON comments
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_comments_update
        BEFORE UPDATE OF book ON comments
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_data_insert
        BEFORE INSERT ON data
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_data_update
        BEFORE UPDATE OF book ON data
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_lrp_insert
        BEFORE INSERT ON last_read_positions
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_lrp_update
        BEFORE UPDATE OF book ON last_read_positions
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_annot_insert
        BEFORE INSERT ON annotations
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_annot_update
        BEFORE UPDATE OF book ON annotations
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_delete_on_authors
        BEFORE DELETE ON authors
        BEGIN
            SELECT CASE
                WHEN (SELECT COUNT(id) FROM books_authors_link WHERE author=OLD.id) > 0
                THEN RAISE(ABORT, 'Foreign key violation: authors is still referenced')
            END;
        END;
CREATE TRIGGER fkc_delete_on_languages
        BEFORE DELETE ON languages
        BEGIN
            SELECT CASE
                WHEN (SELECT COUNT(id) FROM books_languages_link WHERE lang_code=OLD.id) > 0
                THEN RAISE(ABORT, 'Foreign key violation: language is still referenced')
            END;
        END;
CREATE TRIGGER fkc_delete_on_languages_link
        BEFORE INSERT ON books_languages_link
        BEGIN
          SELECT CASE
              WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: book not in books')
              WHEN (SELECT id from languages WHERE id=NEW.lang_code) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: lang_code not in languages')
          END;
        END;
CREATE TRIGGER fkc_delete_on_publishers
        BEFORE DELETE ON publishers
        BEGIN
            SELECT CASE
                WHEN (SELECT COUNT(id) FROM books_publishers_link WHERE publisher=OLD.id) > 0
                THEN RAISE(ABORT, 'Foreign key violation: publishers is still referenced')
            END;
        END;
CREATE TRIGGER fkc_delete_on_series
        BEFORE DELETE ON series
        BEGIN
            SELECT CASE
                WHEN (SELECT COUNT(id) FROM books_series_link WHERE series=OLD.id) > 0
                THEN RAISE(ABORT, 'Foreign key violation: series is still referenced')
            END;
        END;
CREATE TRIGGER fkc_delete_on_tags
        BEFORE DELETE ON tags
        BEGIN
            SELECT CASE
                WHEN (SELECT COUNT(id) FROM books_tags_link WHERE tag=OLD.id) > 0
                THEN RAISE(ABORT, 'Foreign key violation: tags is still referenced')
            END;
        END;
CREATE TRIGGER fkc_insert_books_authors_link
        BEFORE INSERT ON books_authors_link
        BEGIN
          SELECT CASE
              WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: book not in books')
              WHEN (SELECT id from authors WHERE id=NEW.author) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: author not in authors')
          END;
        END;
CREATE TRIGGER fkc_insert_books_publishers_link
        BEFORE INSERT ON books_publishers_link
        BEGIN
          SELECT CASE
              WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: book not in books')
              WHEN (SELECT id from publishers WHERE id=NEW.publisher) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: publisher not in publishers')
          END;
        END;
CREATE TRIGGER fkc_insert_books_ratings_link
        BEFORE INSERT ON books_ratings_link
        BEGIN
          SELECT CASE
              WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: book not in books')
              WHEN (SELECT id from ratings WHERE id=NEW.rating) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: rating not in ratings')
          END;
        END;
CREATE TRIGGER fkc_insert_books_series_link
        BEFORE INSERT ON books_series_link
        BEGIN
          SELECT CASE
              WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: book not in books')
              WHEN (SELECT id from series WHERE id=NEW.series) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: series not in series')
          END;
        END;
CREATE TRIGGER fkc_insert_books_tags_link
        BEFORE INSERT ON books_tags_link
        BEGIN
          SELECT CASE
              WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: book not in books')
              WHEN (SELECT id from tags WHERE id=NEW.tag) IS NULL
              THEN RAISE(ABORT, 'Foreign key violation: tag not in tags')
          END;
        END;
CREATE TRIGGER fkc_update_books_authors_link_a
        BEFORE UPDATE OF book ON books_authors_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_update_books_authors_link_b
        BEFORE UPDATE OF author ON books_authors_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from authors WHERE id=NEW.author) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: author not in authors')
            END;
        END;
CREATE TRIGGER fkc_update_books_languages_link_a
        BEFORE UPDATE OF book ON books_languages_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_update_books_languages_link_b
        BEFORE UPDATE OF lang_code ON books_languages_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from languages WHERE id=NEW.lang_code) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: lang_code not in languages')
            END;
        END;
CREATE TRIGGER fkc_update_books_publishers_link_a
        BEFORE UPDATE OF book ON books_publishers_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_update_books_publishers_link_b
        BEFORE UPDATE OF publisher ON books_publishers_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from publishers WHERE id=NEW.publisher) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: publisher not in publishers')
            END;
        END;
CREATE TRIGGER fkc_update_books_ratings_link_a
        BEFORE UPDATE OF book ON books_ratings_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_update_books_ratings_link_b
        BEFORE UPDATE OF rating ON books_ratings_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from ratings WHERE id=NEW.rating) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: rating not in ratings')
            END;
        END;
CREATE TRIGGER fkc_update_books_series_link_a
        BEFORE UPDATE OF book ON books_series_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_update_books_series_link_b
        BEFORE UPDATE OF series ON books_series_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from series WHERE id=NEW.series) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: series not in series')
            END;
        END;
CREATE TRIGGER fkc_update_books_tags_link_a
        BEFORE UPDATE OF book ON books_tags_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from books WHERE id=NEW.book) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: book not in books')
            END;
        END;
CREATE TRIGGER fkc_update_books_tags_link_b
        BEFORE UPDATE OF tag ON books_tags_link
        BEGIN
            SELECT CASE
                WHEN (SELECT id from tags WHERE id=NEW.tag) IS NULL
                THEN RAISE(ABORT, 'Foreign key violation: tag not in tags')
            END;
        END;
CREATE TRIGGER series_insert_trg
        AFTER INSERT ON series
        BEGIN
          UPDATE series SET sort=title_sort(NEW.name) WHERE id=NEW.id;
        END;
CREATE TRIGGER series_update_trg
        AFTER UPDATE ON series
        BEGIN
          UPDATE series SET sort=title_sort(NEW.name) WHERE id=NEW.id;
        END;
''');

    await _createLibraryFolders(dirname(db.path));
  }

  /// Creates the hidden folders Calibre keeps next to metadata.db:
  ///   .calnotes/        - notes for authors/tags/series etc. Calibre
  ///                       creates notes.db inside it with its own schema
  ///                       the first time it opens the library, so only
  ///                       the folder is made here.
  ///   .caltrash/b, /f   - the Calibre trash bin (deleted books / deleted
  ///                       formats), same layout as ensure_trash_dir().
  /// On Windows both are marked hidden + not-content-indexed, as Calibre
  /// does.
  Future<void> _createLibraryFolders(String libraryDir) async {
    final notesDir = Directory(join(libraryDir, '.calnotes'));
    final trashDir = Directory(join(libraryDir, '.caltrash'));
    await notesDir.create(recursive: true);
    await Directory(join(trashDir.path, 'b')).create(recursive: true);
    await Directory(join(trashDir.path, 'f')).create(recursive: true);

    if (Platform.isWindows) {
      for (final dir in [notesDir, trashDir]) {
        try {
          await Process.run('attrib', ['+H', '+I', dir.path]);
        } catch (_) {
          // Hiding is cosmetic - never fail library creation over it.
        }
      }
    }
  }
}
