import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// The files of a zip-based document (DOCX, ODT), read on demand.
class ZipFiles {
  ZipFiles._(this._entries);

  final Map<String, ArchiveFile> _entries;

  /// Opens [bytes] as a zip. Throws [FormatException]-like errors from
  /// `archive` if it isn't one.
  factory ZipFiles.open(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return ZipFiles._({
      for (final file in archive.files)
        if (file.isFile) p.posix.normalize(file.name): file,
    });
  }

  bool contains(String path) => _entries.containsKey(path);

  Iterable<String> get paths => _entries.keys;

  /// Bytes of [path], or null if missing.
  Uint8List? data(String path) => _entries[path]?.content;

  /// [path] parsed as XML, or null if missing.
  XmlDocument? xml(String path) {
    final bytes = data(path);
    if (bytes == null) return null;
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    return XmlDocument.parse(text.trimLeft());
  }
}

/// Namespace-agnostic helpers (by local name), so they work the same with
/// every `xml` package version.
extension XmlLocalNames on XmlElement {
  String get local => name.local;

  /// Child elements named [localName].
  Iterable<XmlElement> kids(String localName) =>
      childElements.where((e) => e.name.local == localName);

  /// First child element named [localName], or null.
  XmlElement? kid(String localName) {
    for (final e in childElements) {
      if (e.name.local == localName) return e;
    }
    return null;
  }

  /// All descendant elements named [localName], in document order.
  Iterable<XmlElement> deep(String localName) => descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == localName);

  /// Attribute value by local name (any prefix), or null.
  String? attr(String localName) {
    for (final a in attributes) {
      if (a.name.local == localName) return a.value;
    }
    return null;
  }
}

/// Text cleaning for document properties.
class OfficeText {
  OfficeText._();

  static String clean(String? s) =>
      (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Author names Word / LibreOffice fill in by themselves (the computer's
  /// user account), not real authors.
  static bool isJunkAuthor(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return true;
    return const {
          'user', 'admin', 'administrator', 'owner', 'unknown', 'author',
          'windows user', 'windows-felhasználó', 'felhasználó', 'rendszergazda',
          'microsoft office user', 'microsoft office felhasználó', 'valaki',
          'ismeretlen', 'pc', 'home', 'test', 'teszt',
        }.contains(n) ||
        RegExp(r'^(user|admin|pc|desktop)[-_ ]?\d*$').hasMatch(n);
  }

  /// A document title worth keeping: not empty, not "Microsoft Word -
  /// file.doc", not just the file name of a template.
  static String cleanTitle(String title) {
    var t = clean(title);
    t = t.replaceFirst(
        RegExp(r'^microsoft (word|office word)\s*-\s*', caseSensitive: false),
        '');
    if (RegExp(r'\.(docx?|odt|rtf|dotx?)$', caseSensitive: false)
        .hasMatch(t)) {
      t = t.replaceFirst(RegExp(r'\.\w+$'), '');
    }
    const junk = {'untitled', 'document', 'dokumentum', 'névtelen', 'cím', 'title'};
    return junk.contains(t.toLowerCase()) ? '' : t;
  }
}

/// Relationships of Office Open XML (DOCX) parts.
class OfficeRels {
  OfficeRels._();

  /// The main document part (normally word/document.xml), from
  /// _rels/.rels.
  static String mainDocumentPath(ZipFiles zip) {
    final rels = zip.xml('_rels/.rels');
    for (final rel in rels?.rootElement.kids('Relationship') ??
        const <XmlElement>[]) {
      final type = rel.attr('Type') ?? '';
      final target = rel.attr('Target');
      if (type.endsWith('/officeDocument') && target != null) {
        final path = p.posix.normalize(target.replaceFirst(RegExp('^/'), ''));
        if (zip.contains(path)) return path;
      }
    }
    return 'word/document.xml';
  }

  /// Relationship id -> target path inside the zip (or URL, for external
  /// targets) for the part [partPath].
  static Map<String, String> relationships(ZipFiles zip, String partPath) {
    final dir = p.posix.dirname(partPath);
    final rels = zip.xml('$dir/_rels/${p.posix.basename(partPath)}.rels');
    final map = <String, String>{};
    for (final rel in rels?.rootElement.kids('Relationship') ??
        const <XmlElement>[]) {
      final id = rel.attr('Id');
      final target = rel.attr('Target');
      if (id == null || target == null) continue;
      if (rel.attr('TargetMode') == 'External') {
        map[id] = target;
      } else if (target.startsWith('/')) {
        map[id] = p.posix.normalize(target.substring(1));
      } else {
        map[id] = p.posix.normalize(p.posix.join(dir, target));
      }
    }
    return map;
  }
}
