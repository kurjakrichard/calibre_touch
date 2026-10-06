import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../book_metadata.dart';
import '../calibre.dart';
import '../cover_image.dart';
import '../metadata_reader.dart';
import 'mobi_file.dart';

/// MOBI / AZW / AZW3 (KF8) / PRC: title, authors, ... from the EXTH header
/// (the same records Calibre reads), cover from the EXTH cover offset.
///
/// DRM-protected books still have readable metadata and cover.
class MobiMetadataReader extends MetadataReader {
  const MobiMetadataReader();

  @override
  Set<String> get extensions => const {'mobi', 'azw', 'azw3', 'azw4', 'prc'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() => parseMobiMetadata(File(filePath).readAsBytesSync(),
          withCover: withCover));
}

/// Parses the bytes of a MOBI-family file. Pure Dart, safe in an isolate.
Future<BookMetadata> parseMobiMetadata(Uint8List bytes,
    {bool withCover = true}) async {
  final mobi = await MobiFile.parse(bytes);

  var title = mobi.exthString(MobiFile.exthUpdatedTitle);
  if (title.isEmpty) title = mobi.fullName;
  if (title.isEmpty) title = mobi.pdbName;

  final authors = <String>[
    for (final value in mobi.exthStrings(MobiFile.exthAuthor))
      ...Calibre.stringToAuthors(value),
  ].where((a) => a != Calibre.unknown).toSet().toList();

  final tags = <String>{
    for (final value in mobi.exthStrings(MobiFile.exthSubject))
      for (final tag in value.split(';'))
        if (tag.trim().isNotEmpty) tag.trim(),
  }.toList();

  DateTime? pubdate;
  final rawDate = mobi.exthString(MobiFile.exthPublishingDate);
  if (rawDate.isNotEmpty) {
    pubdate = Calibre.parseDate(rawDate);
    // Calibre writes 0101-01-01 for "no date".
    if (pubdate != null && pubdate.year <= 101) pubdate = null;
  }

  final identifiers = <String, String>{};
  for (final isbn in mobi.exthStrings(MobiFile.exthIsbn)) {
    final entry = Calibre.identifier('isbn', isbn);
    if (entry != null) {
      identifiers[entry.key] = entry.value;
      break;
    }
  }
  final asin = mobi.exthString(MobiFile.exthAsin);
  if (asin.isNotEmpty) {
    // Calibre keeps EXTH 113 as "mobi-asin" (for its own books it holds
    // the book's uuid).
    final entry = Calibre.identifier('mobi-asin', asin);
    if (entry != null) identifiers[entry.key] = entry.value;
  }

  final languages = <String>[];
  for (final value in mobi.exthStrings(MobiFile.exthLanguage)) {
    final code = Calibre.languageCode(value);
    if (code != null && !languages.contains(code)) languages.add(code);
  }
  if (languages.isEmpty) {
    final fromLocale = _localeLanguage(mobi.data.mobiHeader?.locale);
    if (fromLocale != null) languages.add(fromLocale);
  }

  Uint8List? cover;
  if (withCover) {
    final image = mobi.cover;
    if (image != null) cover = CoverImage.toJpeg(image);
  }

  return BookMetadata(
    title: title,
    titleSort: mobi.exthString(MobiFile.exthTitleFileAs),
    authors: authors,
    authorSort:
        authors.isEmpty ? '' : mobi.exthString(MobiFile.exthCreatorFileAs),
    publisher: mobi.exthString(MobiFile.exthPublisher),
    pubdate: pubdate,
    description: mobi.exthString(MobiFile.exthDescription),
    tags: tags,
    languages: languages,
    identifiers: identifiers,
    cover: cover,
    // format: left empty - taken from the file extension (MOBI, AZW3, ...)
    // like Calibre does.
  );
}

/// Main language of the MOBI header's Windows locale id (low byte), as a
/// Calibre language code. Only the common ones.
String? _localeLanguage(int? locale) {
  if (locale == null || locale == MobiFile.notSet) return null;
  const languages = {
    0x01: 'ara', 0x02: 'bul', 0x03: 'cat', 0x04: 'zho', 0x05: 'ces', //
    0x06: 'dan', 0x07: 'deu', 0x08: 'ell', 0x09: 'eng', 0x0A: 'spa',
    0x0B: 'fin', 0x0C: 'fra', 0x0D: 'heb', 0x0E: 'hun', 0x0F: 'isl',
    0x10: 'ita', 0x11: 'jpn', 0x12: 'kor', 0x13: 'nld', 0x14: 'nor',
    0x15: 'pol', 0x16: 'por', 0x18: 'ron', 0x19: 'rus', 0x1A: 'hrv',
    0x1B: 'slk', 0x1D: 'swe', 0x1F: 'tur', 0x22: 'ukr', 0x24: 'slv',
  };
  return languages[locale & 0xFF];
}
