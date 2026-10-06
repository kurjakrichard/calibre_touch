/// Reading metadata (title, authors, cover, ...) from book files, and
/// Calibre's naming/sorting conventions.
///
/// ```dart
/// final metadata = await MetadataReaders.read(filePath);
/// ```
library;

export 'book_metadata.dart';
export 'calibre.dart';
export 'cover_image.dart';
export 'metadata_reader.dart';
export 'metadata_readers.dart';
export 'opf_library_scan.dart';
export 'opf_writer.dart';
export 'readers/epub_metadata_reader.dart';
export 'readers/fb2_metadata_reader.dart';
export 'readers/mobi_file.dart';
export 'readers/mobi_metadata_reader.dart';
export 'readers/office_files.dart';
export 'readers/office_metadata_readers.dart';
export 'readers/opf_metadata.dart';
export 'readers/pdf_metadata_reader.dart';
export 'readers/pdf_raw_metadata.dart';
export 'readers/rtf_parser.dart';
export 'readers/txt_metadata_reader.dart';
export 'readers/txt_text.dart';
