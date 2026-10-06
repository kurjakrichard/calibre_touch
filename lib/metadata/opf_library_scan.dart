import 'dart:io';
import 'dart:isolate';

// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'book_metadata.dart';
import 'calibre.dart';
import 'opf_writer.dart';
import 'readers/opf_metadata.dart';

/// One book file found next to a metadata.opf (one `data` row).
class OpfBookFormat {
  const OpfBookFormat(
      {required this.format, required this.name, required this.size});

  /// Upper case, as Calibre stores it: EPUB, PDF, ...
  final String format;

  /// File name without the extension (data.name).
  final String name;
  final int size;
}

/// A book folder of a Calibre library, read back from its metadata.opf -
/// everything needed to recreate the book's rows in metadata.db.
class OpfLibraryBook {
  const OpfLibraryBook({
    required this.id,
    required this.path,
    required this.uuid,
    required this.metadata,
    required this.authors,
    required this.timestamp,
    required this.pubdate,
    required this.hasCover,
    required this.formats,
  });

  /// The book id from the folder name `Title (12)` or, failing that, from
  /// the OPF's calibre identifier. Null if neither has one.
  final int? id;

  /// Folder relative to the library root, '/' separated (books.path).
  final String path;

  /// From the OPF; '' if it has none (a new one is made).
  final String uuid;

  /// Title, title sort, publisher, description (HTML), series, tags,
  /// languages, identifiers, rating.
  final BookMetadata metadata;

  /// Authors with their sort form (opf:file-as, or computed).
  final List<OpfAuthor> authors;

  /// books.timestamp (date added) in Calibre's format.
  final String timestamp;

  /// books.pubdate in Calibre's format (undefined date if none).
  final String pubdate;

  final bool hasCover;
  final List<OpfBookFormat> formats;
}

/// Result of [OpfLibraryScan.scan].
class OpfLibraryScanResult {
  const OpfLibraryScanResult(this.books, this.failedFolders);

  final List<OpfLibraryBook> books;

  /// Folders whose metadata.opf could not be read (relative paths).
  final List<String> failedFolders;
}

/// Finds every book folder (a folder with a metadata.opf) of a Calibre
/// library and reads it back - the input of "rebuild the database from
/// the metadata.opf files", like Calibre's Library maintenance >
/// Restore database (calibre/db/restore.py).
class OpfLibraryScan {
  OpfLibraryScan._();

  /// File extensions Calibre treats as book formats (BOOK_EXTENSIONS);
  /// other files in a book folder (cover.jpg, metadata.opf, ...) are not
  /// formats.
  static const Set<String> bookExtensions = {
    'azw', 'azw1', 'azw3', 'azw4', 'book', 'cb7', 'cbc', 'cbr', 'cbz',
    'chm', 'djv', 'djvu', 'doc', 'docm', 'docx', 'epub', 'fb2', 'fbz',
    'htm', 'html', 'htmlz', 'iba', 'ibook', 'ibooks', 'imp', 'kepub',
    'kfx', 'kpf', 'lit', 'lrf', 'lrx', 'markdown', 'mbp', 'md', 'mobi',
    'odt', 'oebzip', 'oxps', 'pdb', 'pdf', 'pdr', 'pml', 'pmlz', 'pobi',
    'prc', 'ps', 'rar', 'rb', 'rtf', 'snb', 'tan', 'text', 'textile',
    'tpz', 'txt', 'txtz', 'updb', 'xhtm', 'xhtml', 'xps', 'zbf', 'zip',
  };

  static final RegExp _folderId = RegExp(r'\((\d+)\)$');

  /// Scans [libraryRoot] in a background isolate. Hidden folders
  /// (.caltrash - which holds OPFs of deleted books -, .calnotes, ...) are
  /// skipped. Books are sorted by id, books without an id last.
  static Future<OpfLibraryScanResult> scan(String libraryRoot) =>
      Isolate.run(() => scanSync(libraryRoot));

  static OpfLibraryScanResult scanSync(String libraryRoot) {
    final books = <OpfLibraryBook>[];
    final failed = <String>[];

    void walk(Directory dir) {
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return; // unreadable folder
      }
      final files = entries.whereType<File>().toList();
      if (dir.path != libraryRoot &&
          files.any((f) => p.basename(f.path) == OpfWriter.fileName)) {
        final relative =
            p.relative(dir.path, from: libraryRoot).split(p.separator).join('/');
        try {
          books.add(_readBook(dir, relative, files));
        } catch (_) {
          failed.add(relative);
        }
      }
      for (final sub in entries.whereType<Directory>()) {
        if (p.basename(sub.path).startsWith('.')) continue;
        walk(sub);
      }
    }

    walk(Directory(libraryRoot));
    books.sort((a, b) {
      if (a.id == null) return b.id == null ? a.path.compareTo(b.path) : 1;
      if (b.id == null) return -1;
      return a.id!.compareTo(b.id!);
    });
    return OpfLibraryScanResult(books, failed);
  }

  static OpfLibraryBook _readBook(
      Directory dir, String relativePath, List<File> files) {
    final opfFile = File(p.join(dir.path, OpfWriter.fileName));
    final document = XmlDocument.parse(_stripBom(opfFile.readAsStringSync()));
    final metadata = OpfMetadata.parse(document);

    final element =
        document.findAllElements('metadata', namespace: '*').firstOrNull;
    if (element == null) {
      throw const FormatException('metadata.opf has no <metadata>');
    }

    // calibre id / uuid identifiers (OpfMetadata skips these on purpose).
    int? opfId;
    var uuid = '';
    for (final identifier in element.findAllElements('identifier', namespace: '*')) {
      final scheme = (_attr(identifier, 'scheme') ?? '').toLowerCase();
      final id = identifier.getAttribute('id') ?? '';
      // OPF 2: <dc:identifier opf:scheme="calibre">12</dc:identifier>
      // OPF 3: <dc:identifier id="calibre_id">calibre:12</dc:identifier>
      final value = identifier.innerText.trim();
      final lower = value.toLowerCase();
      if (scheme == 'calibre' || id == 'calibre_id' || lower.startsWith('calibre:')) {
        opfId ??= int.tryParse(
            lower.startsWith('calibre:') ? value.substring(8).trim() : value);
      } else if (scheme == 'uuid' || id == 'uuid_id' || lower.startsWith('urn:uuid:')) {
        if (uuid.isEmpty) {
          uuid = lower.startsWith('urn:uuid:') ? value.substring(9).trim() : value;
        }
      }
    }

    // Author sort per author (opf:file-as of each dc:creator).
    final fileAs = <String, String>{};
    for (final creator in element.findAllElements('creator', namespace: '*')) {
      final sort = _attr(creator, 'file-as')?.trim() ?? '';
      if (sort.isEmpty) continue;
      final names = Calibre.stringToAuthors(
          creator.innerText.replaceAll(RegExp(r'\s+'), ' ').trim());
      if (names.length == 1) fileAs[names.first] = sort;
    }
    final authorNames =
        metadata.authors.isEmpty ? const [Calibre.unknown] : metadata.authors;
    final authors = [
      for (final name in authorNames)
        OpfAuthor(name, fileAs[name] ?? Calibre.authorSort(name)),
    ];

    // Date added: calibre:timestamp, else when metadata.opf was written.
    String? timestamp;
    for (final meta in element.findAllElements('meta', namespace: '*')) {
      // OPF 2: name/content, OPF 3: property + text.
      final isTimestamp = meta.getAttribute('name') == 'calibre:timestamp' ||
          meta.getAttribute('property') == 'calibre:timestamp';
      if (isTimestamp) {
        final t = DateTime.tryParse(
            (meta.getAttribute('content') ?? meta.innerText).trim());
        if (t != null) timestamp = Calibre.formatTimestamp(t);
        break;
      }
    }
    timestamp ??= Calibre.formatTimestamp(opfFile.lastModifiedSync());

    // Formats: book files in the folder, one per extension (data has
    // UNIQUE(book, format)).
    final formats = <String, OpfBookFormat>{};
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in sorted) {
      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      if (!bookExtensions.contains(ext)) continue;
      final format = ext.toUpperCase();
      formats.putIfAbsent(
        format,
        () => OpfBookFormat(
          format: format,
          name: p.basenameWithoutExtension(file.path),
          size: file.lengthSync(),
        ),
      );
    }

    final folderId =
        int.tryParse(_folderId.firstMatch(p.basename(dir.path))?.group(1) ?? '');

    return OpfLibraryBook(
      id: folderId ?? opfId,
      path: relativePath,
      uuid: uuid,
      metadata: metadata.copyWith(
        title: metadata.title.isEmpty ? Calibre.unknown : metadata.title,
      ),
      authors: authors,
      timestamp: timestamp,
      pubdate: metadata.pubdate == null
          ? Calibre.undefinedDate
          : Calibre.formatTimestamp(metadata.pubdate!),
      hasCover: File(p.join(dir.path, 'cover.jpg')).existsSync(),
      formats: formats.values.toList(),
    );
  }

  static String _stripBom(String s) {
    var text = s.startsWith('﻿') ? s.substring(1) : s;
    final start = text.indexOf('<');
    if (start > 0) text = text.substring(start);
    return text;
  }

  static String? _attr(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }
}
