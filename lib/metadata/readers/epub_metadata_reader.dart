import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../book_metadata.dart';
import '../cover_image.dart';
import '../metadata_reader.dart';
import 'opf_metadata.dart';

/// EPUB 2 / EPUB 3: metadata from the OPF package document, cover from the
/// manifest (the same places Calibre looks).
class EpubMetadataReader extends MetadataReader {
  const EpubMetadataReader();

  @override
  Set<String> get extensions => const {'epub', 'kepub'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() => parseEpubMetadata(File(filePath).readAsBytesSync(),
          withCover: withCover));
}

/// Parses the bytes of an .epub file. Pure Dart, safe to call in an
/// isolate. Throws [FormatException] if this is not an EPUB.
BookMetadata parseEpubMetadata(Uint8List bytes, {bool withCover = true}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  // Only the entries are listed here - a file is decompressed when its
  // content is read, and only a few small files are.
  final entries = <String, ArchiveFile>{
    for (final file in archive.files)
      if (file.isFile) p.posix.normalize(file.name): file,
  };

  Uint8List? data(String path) => entries[path]?.content;
  String? text(String path) {
    final content = data(path);
    if (content == null) return null;
    var s = utf8.decode(content, allowMalformed: true);
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    // Some books have blank lines before <?xml ...?>, which XML parsers
    // reject.
    return s.trimLeft();
  }

  // 1) META-INF/container.xml -> path of the OPF (or just the first .opf).
  String? opfPath;
  final containerXml = text('META-INF/container.xml');
  if (containerXml != null) {
    opfPath = XmlDocument.parse(containerXml)
        .findAllElements('rootfile', namespace: '*')
        .map((e) => e.getAttribute('full-path'))
        .whereType<String>()
        .map((path) => p.posix.normalize(_decode(path)))
        .where(entries.containsKey)
        .firstOrNull;
  }
  opfPath ??= entries.keys.where((k) => k.toLowerCase().endsWith('.opf')).firstOrNull;
  if (opfPath == null) throw const FormatException('No OPF file in the EPUB');

  final opf = XmlDocument.parse(text(opfPath)!);
  var metadata = OpfMetadata.parse(opf).copyWith(format: 'EPUB');

  if (withCover) {
    final coverPath = _findCover(opf, opfPath, entries.keys.toSet(), text);
    final coverBytes = coverPath == null ? null : data(coverPath);
    final jpeg = coverBytes == null ? null : CoverImage.toJpeg(coverBytes);
    if (jpeg != null) metadata = metadata.copyWith(cover: jpeg);
  }
  return metadata;
}

/// Path (inside the zip) of the cover image, or null. In order:
/// EPUB 3 `properties="cover-image"`, EPUB 2 `<meta name="cover">`, the
/// guide's cover page, a manifest image called "cover", and finally a
/// first page that holds nothing but one image.
String? _findCover(XmlDocument opf, String opfPath, Set<String> files,
    String? Function(String path) text) {
  final opfDir = p.posix.dirname(opfPath);
  String resolve(String baseDir, String href) =>
      p.posix.normalize(p.posix.join(baseDir, _decode(_stripFragment(href))));

  final items = opf.findAllElements('item', namespace: '*').toList();
  final byId = {
    for (final item in items)
      if (item.getAttribute('id') != null) item.getAttribute('id')!: item,
  };
  String? hrefOf(XmlElement? item) {
    final href = item?.getAttribute('href');
    return href == null ? null : resolve(opfDir, href);
  }

  bool isImage(XmlElement item) =>
      (item.getAttribute('media-type') ?? '').startsWith('image/') &&
      item.getAttribute('media-type') != 'image/svg+xml';

  // An image, or an XHTML page whose (first) image is the cover.
  String? imageFrom(String? path) {
    if (path == null || !files.contains(path)) return null;
    final lower = path.toLowerCase();
    if (!(lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.xml'))) {
      return path;
    }
    final page = text(path);
    if (page == null) return null;
    final src = _imageSources(page).firstOrNull;
    if (src == null) return null;
    final target = resolve(p.posix.dirname(path), src);
    return files.contains(target) ? target : null;
  }

  // 1) EPUB 3
  for (final item in items) {
    final properties = (item.getAttribute('properties') ?? '').split(' ');
    if (properties.contains('cover-image')) {
      final found = imageFrom(hrefOf(item));
      if (found != null) return found;
    }
  }

  // 2) EPUB 2: <meta name="cover" content="manifest-id"/>
  for (final meta in opf.findAllElements('meta', namespace: '*')) {
    if (meta.getAttribute('name') != 'cover') continue;
    final content = meta.getAttribute('content');
    if (content == null) continue;
    final found = imageFrom(hrefOf(byId[content])) ??
        // some books put the href instead of the id there
        imageFrom(resolve(opfDir, content));
    if (found != null) return found;
  }

  // 3) <guide><reference type="cover" href="..."/>
  for (final reference in opf.findAllElements('reference', namespace: '*')) {
    final type = (reference.getAttribute('type') ?? '').toLowerCase();
    if (type != 'cover' && type != 'other.ms-coverimage-standard') continue;
    final href = reference.getAttribute('href');
    if (href == null) continue;
    final found = imageFrom(resolve(opfDir, href));
    if (found != null) return found;
  }

  // 4) a manifest image whose id or file name says "cover"
  for (final item in items.where(isImage)) {
    final id = (item.getAttribute('id') ?? '').toLowerCase();
    final href = (item.getAttribute('href') ?? '').toLowerCase();
    if (id.contains('cover') || p.posix.basename(href).contains('cover')) {
      final found = imageFrom(hrefOf(item));
      if (found != null) return found;
    }
  }

  // 5) a first page that is just one picture (a title page)
  final firstRef = opf
      .findAllElements('itemref', namespace: '*')
      .map((r) => byId[r.getAttribute('idref')])
      .whereType<XmlElement>()
      .firstOrNull;
  final firstPath = hrefOf(firstRef);
  if (firstPath != null) {
    final page = text(firstPath);
    if (page != null) {
      final bodyStart = page.toLowerCase().indexOf('<body');
      final body = bodyStart < 0 ? page : page.substring(bodyStart);
      final plain = body
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'&[#\w]+;'), ' ')
          .replaceAll(RegExp(r'\s+'), '');
      if (_imageSources(body).length == 1 && plain.length < 100) {
        return imageFrom(firstPath);
      }
    }
  }
  return null;
}

/// `src` of every <img> and `href`/`xlink:href` of every SVG <image> in an
/// (X)HTML page, in document order.
List<String> _imageSources(String page) => [
      for (final m in RegExp(
              r'''<(?:img\b[^>]*?\bsrc|image\b[^>]*?\b(?:xlink:)?href)\s*=\s*(["'])(.*?)\1''',
              caseSensitive: false,
              dotAll: true)
          .allMatches(page))
        m.group(2)!.trim(),
    ];

String _stripFragment(String href) {
  final hash = href.indexOf('#');
  return hash < 0 ? href : href.substring(0, hash);
}

String _decode(String s) {
  try {
    return Uri.decodeFull(s);
  } catch (_) {
    return s;
  }
}
