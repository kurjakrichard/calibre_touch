import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import 'book_metadata.dart';
import 'metadata_reader.dart';
import 'readers/epub_metadata_reader.dart';
import 'readers/pdf_metadata_reader.dart';

/// Entry point for reading metadata from book files:
///
/// ```dart
/// final metadata = await MetadataReaders.read(path);
/// ```
///
/// Picks the [MetadataReader] for the file's extension. Formats without a
/// reader, and files a reader can't parse, still get a title/author from
/// the file name ([BookMetadata.fromFileName]) - so this never throws.
class MetadataReaders {
  MetadataReaders._();

  static final List<MetadataReader> _readers = [
    const EpubMetadataReader(),
    const PdfMetadataReader(),
  ];

  /// Adds a reader. Registered later = asked first, so a reader can also
  /// replace a built-in one for the same extension.
  static void register(MetadataReader reader) => _readers.insert(0, reader);

  /// Extensions (lower case, no dot) that have a real metadata reader.
  static Set<String> get supportedExtensions =>
      {for (final r in _readers) ...r.extensions};

  /// The reader for [filePath]'s extension, or null.
  static MetadataReader? forFile(String filePath) {
    final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
    for (final reader in _readers) {
      if (reader.extensions.contains(ext)) return reader;
    }
    return null;
  }

  /// Reads the metadata of [filePath]. Never throws: missing fields (or
  /// everything, for unknown formats / damaged files) come from the file
  /// name.
  static Future<BookMetadata> read(String filePath,
      {bool withCover = true}) async {
    final fallback = BookMetadata.fromFileName(filePath);
    final reader = forFile(filePath);
    if (reader == null) return fallback;
    try {
      final metadata = await reader.read(filePath, withCover: withCover);
      return metadata.mergedWith(fallback);
    } catch (e, st) {
      debugPrint('Metadata not read from $filePath: $e\n$st');
      return fallback;
    }
  }
}
