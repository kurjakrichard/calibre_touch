import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// One reading-order part of the book (an XHTML file from the OPF spine).
class EpubSection {
  const EpubSection({required this.href, required this.html});

  /// Path inside the EPUB zip, e.g. `OEBPS/Text/chapter1.xhtml`.
  final String href;

  /// Contents of the `<body>` element.
  final String html;
}

/// One entry of the table of contents.
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.href,
    required this.sectionIndex,
    required this.depth,
  });

  final String title;

  /// Target file inside the zip (without #fragment).
  final String href;

  /// Index into [EpubDocument.sections], -1 if the file isn't in the spine.
  final int sectionIndex;

  /// 0 for chapters, 1 for sub-chapters, ...
  final int depth;
}

/// A parsed EPUB (2 or 3): metadata, spine sections, table of contents and
/// the raw files (images, ...) needed to render it.
///
/// Parsed with `archive` + `xml` + `html` only, so it works on every
/// platform (Windows, Android, ...). Use [EpubDocument.parse] in an isolate
/// (`compute`) for big books.
class EpubDocument {
  EpubDocument._({
    required this.title,
    required this.author,
    required this.sections,
    required this.toc,
    required this.files,
  });

  final String title;
  final String author;
  final List<EpubSection> sections;
  final List<EpubTocEntry> toc;

  /// Every file of the zip by its normalized path.
  final Map<String, Uint8List> files;

  /// Index of the section stored at [href] (fragment ignored), or -1.
  int sectionIndexOf(String href) {
    final path = stripFragment(href);
    return sections.indexWhere((s) => s.href == path);
  }

  /// Resolves a link/image [ref] found in the section at [fromHref].
  static String resolve(String fromHref, String ref) {
    final decoded = _decode(stripFragment(ref));
    if (decoded.isEmpty) return stripFragment(fromHref);
    return p.posix.normalize(p.posix.join(p.posix.dirname(fromHref), decoded));
  }

  static String stripFragment(String href) {
    final hash = href.indexOf('#');
    return hash < 0 ? href : href.substring(0, hash);
  }

  static String _decode(String s) {
    try {
      return Uri.decodeFull(s);
    } catch (_) {
      return s;
    }
  }

  /// Parses the bytes of an .epub file. Throws [FormatException] if it is
  /// not a valid EPUB.
  static EpubDocument parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      files[p.posix.normalize(file.name)] = file.content;
    }

    String text(String path) {
      final data = files[path];
      if (data == null) throw FormatException('Missing file in EPUB: $path');
      return utf8.decode(data, allowMalformed: true);
    }

    // 1) META-INF/container.xml -> path of the .opf package file.
    final container = XmlDocument.parse(text('META-INF/container.xml'));
    final opfPath = container
        .findAllElements('rootfile', namespace: '*')
        .map((e) => e.getAttribute('full-path'))
        .whereType<String>()
        .first;
    final opfDir = p.posix.dirname(opfPath);
    String inOpf(String href) => p.posix
        .normalize(p.posix.join(opfDir, _decode(stripFragment(href))));

    // 2) The package: metadata, manifest, spine.
    final opf = XmlDocument.parse(text(opfPath));
    List<String> meta(String name) => opf
        .findAllElements(name, namespace: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final manifest = <String, XmlElement>{};
    for (final item in opf.findAllElements('item', namespace: '*')) {
      final id = item.getAttribute('id');
      if (id != null) manifest[id] = item;
    }

    final sections = <EpubSection>[];
    final spine = opf.findAllElements('spine', namespace: '*').firstOrNull;
    for (final ref in spine?.findElements('itemref', namespace: '*') ??
        const <XmlElement>[]) {
      final item = manifest[ref.getAttribute('idref')];
      final href = item?.getAttribute('href');
      if (href == null) continue;
      final path = inOpf(href);
      if (!files.containsKey(path)) continue;
      final document = html_parser.parse(text(path));
      sections.add(EpubSection(
        href: path,
        html: document.body?.innerHtml ?? '',
      ));
    }
    if (sections.isEmpty) {
      throw const FormatException('The EPUB has no readable content');
    }

    int indexOf(String href) {
      final path = stripFragment(href);
      return sections.indexWhere((s) => s.href == path);
    }

    // 3) Table of contents: EPUB 3 nav document, or EPUB 2 NCX.
    final toc = <EpubTocEntry>[];
    final navItem = manifest.values.where((i) =>
        (i.getAttribute('properties') ?? '').split(' ').contains('nav'));
    final ncxId = spine?.getAttribute('toc');
    final ncxItem = manifest[ncxId] ??
        manifest.values
            .where((i) => i.getAttribute('media-type') ==
                'application/x-dtbncx+xml')
            .firstOrNull;

    if (navItem.isNotEmpty) {
      final navPath = inOpf(navItem.first.getAttribute('href')!);
      if (files.containsKey(navPath)) {
        final nav = html_parser.parse(text(navPath));
        final navs = nav.getElementsByTagName('nav');
        final tocNav = navs.firstWhere(
          (n) => (n.attributes['epub:type'] ?? n.attributes['type'] ?? '')
              .contains('toc'),
          orElse: () => navs.isNotEmpty ? navs.first : dom.Element.tag('nav'),
        );
        void walk(dom.Element list, int depth) {
          for (final li in list.children.where((c) => c.localName == 'li')) {
            final link = li.children
                .where((c) => c.localName == 'a' || c.localName == 'span')
                .firstOrNull;
            final href = link?.attributes['href'];
            final title = link?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (href != null && title != null && title.isNotEmpty) {
              final target = resolve(navPath, href);
              toc.add(EpubTocEntry(
                title: title,
                href: target,
                sectionIndex: indexOf(target),
                depth: depth,
              ));
            }
            for (final sub in li.children.where((c) => c.localName == 'ol')) {
              walk(sub, depth + 1);
            }
          }
        }

        for (final ol in tocNav.children.where((c) => c.localName == 'ol')) {
          walk(ol, 0);
        }
      }
    }

    if (toc.isEmpty && ncxItem != null) {
      final ncxPath = inOpf(ncxItem.getAttribute('href')!);
      if (files.containsKey(ncxPath)) {
        final ncx = XmlDocument.parse(text(ncxPath));
        void walk(XmlElement parent, int depth) {
          for (final point
              in parent.findElements('navPoint', namespace: '*')) {
            final title = point
                    .findElements('navLabel', namespace: '*')
                    .firstOrNull
                    ?.innerText
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim() ??
                '';
            final src = point
                .findElements('content', namespace: '*')
                .firstOrNull
                ?.getAttribute('src');
            if (src != null && title.isNotEmpty) {
              final target = resolve(ncxPath, src);
              toc.add(EpubTocEntry(
                title: title,
                href: target,
                sectionIndex: indexOf(target),
                depth: depth,
              ));
            }
            walk(point, depth + 1);
          }
        }

        final navMap = ncx.findAllElements('navMap', namespace: '*');
        if (navMap.isNotEmpty) walk(navMap.first, 0);
      }
    }

    return EpubDocument._(
      title: meta('title').firstOrNull ?? '',
      author: meta('creator').join(' & '),
      sections: sections,
      toc: toc,
      files: files,
    );
  }
}
