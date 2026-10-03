import 'book_metadata.dart';

/// Reads the metadata of one kind of book file.
///
/// To support a new format (MOBI, AZW3, FB2, CBZ, ...): implement this
/// class and add an instance to [MetadataReaders] (or call
/// [MetadataReaders.register]). Nothing else needs to change - importing
/// goes through [MetadataReaders.read].
abstract class MetadataReader {
  const MetadataReader();

  /// File extensions this reader handles: lower case, without the dot.
  Set<String> get extensions;

  /// Reads [filePath]. Heavy parsing should run off the UI isolate
  /// (`Isolate.run`). May throw on damaged files - [MetadataReaders.read]
  /// catches that and falls back to the file name.
  ///
  /// With [withCover] false, the cover is not extracted (faster).
  Future<BookMetadata> read(String filePath, {bool withCover = true});
}
