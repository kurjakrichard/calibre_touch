import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../book_metadata.dart';
import '../calibre.dart';
import '../cover_image.dart';
import '../metadata_reader.dart';
import 'office_files.dart';
import 'txt_text.dart';

/// An opened FictionBook (.fb2, or .fbz / .fb2.zip = zipped FB2).
class Fb2File {
  Fb2File._(this.root);

  /// The `<FictionBook>` element.
  final XmlElement root;

  /// Parses FB2 (or a zip with an .fb2 inside). The XML declaration's
  /// encoding is honoured (most Russian FB2 files are windows-1251).
  factory Fb2File.parse(Uint8List bytes) {
    var data = bytes;
    if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      // PK.. = zip (.fbz)
      final zip = ZipFiles.open(bytes);
      final inner = zip.paths.firstWhere(
          (path) => path.toLowerCase().endsWith('.fb2'),
          orElse: () => throw const FormatException('No .fb2 in the archive'));
      data = zip.data(inner)!;
    }
    var text = TxtText.decodeXml(data);
    if (text.startsWith('﻿')) text = text.substring(1);
    final root = XmlDocument.parse(text.trimLeft()).rootElement;
    if (root.local != 'FictionBook') {
      throw const FormatException('Not a FictionBook file');
    }
    return Fb2File._(root);
  }

  XmlElement? get description => root.kid('description');
  XmlElement? get titleInfo => description?.kid('title-info');

  /// Pictures stored in the file: id -> bytes (base64 `<binary>`).
  Map<String, Uint8List> get binaries {
    final out = <String, Uint8List>{};
    for (final b in root.kids('binary')) {
      final id = b.attr('id');
      if (id == null) continue;
      try {
        out[id] = base64.decode(b.innerText.replaceAll(RegExp(r'\s+'), ''));
      } on FormatException {
        // A broken picture: leave it out.
      }
    }
    return out;
  }

  /// Target id of an FB2 link (`l:href="#cover.jpg"` -> `cover.jpg`).
  static String? linkTarget(XmlElement e) {
    final href = e.attr('href');
    if (href == null || !href.startsWith('#')) return null;
    return href.substring(1);
  }

  /// "First Middle Last" (or the nickname) of an `<author>`.
  static String authorName(XmlElement author) {
    String part(String name) => OfficeText.clean(author.kid(name)?.innerText);
    final name = [part('first-name'), part('middle-name'), part('last-name')]
        .where((s) => s.isNotEmpty)
        .join(' ');
    return name.isNotEmpty ? name : part('nickname');
  }
}

/// FictionBook 2 (.fb2, .fbz): title, authors, series, annotation,
/// keywords, language, publisher, year, ISBN and cover from the
/// `<description>`, the way Calibre reads them.
class Fb2MetadataReader extends MetadataReader {
  const Fb2MetadataReader();

  @override
  Set<String> get extensions => const {'fb2', 'fbz'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() => parseFb2Metadata(File(filePath).readAsBytesSync(),
          withCover: withCover));
}

BookMetadata parseFb2Metadata(Uint8List bytes, {bool withCover = true}) {
  final fb2 = Fb2File.parse(bytes);
  final info = fb2.titleInfo;
  final publish = fb2.description?.kid('publish-info');
  String clean(XmlElement? e) => OfficeText.clean(e?.innerText);

  final authors = <String>[
    for (final a in info?.kids('author') ?? const <XmlElement>[])
      if (Fb2File.authorName(a).isNotEmpty) Fb2File.authorName(a),
  ];

  // Annotation: <p> paragraphs -> HTML, like the description of an EPUB.
  final annotation = info?.kid('annotation');
  final description = annotation == null
      ? ''
      : annotation
          .kids('p')
          .map((p) => '<p>${_escape(clean(p))}</p>')
          .where((p) => p != '<p></p>')
          .join();

  final sequence = info?.kid('sequence');
  final series = OfficeText.clean(sequence?.attr('name'));

  DateTime? pubdate;
  final year = clean(publish?.kid('year'));
  if (year.isNotEmpty) pubdate = Calibre.parseDate(year);
  pubdate ??= Calibre.parseDate(info?.kid('date')?.attr('value') ?? '');

  final identifiers = <String, String>{};
  final isbn = Calibre.identifier('isbn', clean(publish?.kid('isbn')));
  if (isbn != null) identifiers[isbn.key] = isbn.value;

  final language = Calibre.languageCode(clean(info?.kid('lang')));

  Uint8List? cover;
  if (withCover) {
    final image = info?.kid('coverpage')?.kid('image');
    final id = image == null ? null : Fb2File.linkTarget(image);
    final data = id == null ? null : fb2.binaries[id];
    if (data != null) cover = CoverImage.toJpeg(data);
  }

  return BookMetadata(
    title: clean(info?.kid('book-title')),
    authors: authors,
    description: description,
    publisher: clean(publish?.kid('publisher')),
    pubdate: pubdate,
    series: series,
    seriesIndex: series.isEmpty
        ? null
        : double.tryParse(sequence?.attr('number') ?? '') ?? 1,
    tags: {
      for (final k in clean(info?.kid('keywords')).split(','))
        if (k.trim().isNotEmpty) k.trim(),
    }.toList(),
    languages: language == null ? const [] : [language],
    identifiers: identifiers,
    cover: cover,
  );
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
