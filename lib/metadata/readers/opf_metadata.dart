import 'package:xml/xml.dart';

import '../book_metadata.dart';
import '../calibre.dart';

/// Reads Calibre-relevant metadata from an OPF package document - the
/// `content.opf` inside an EPUB, or the `metadata.opf` Calibre keeps in
/// every book folder. Handles OPF 2 (`opf:role`, `opf:file-as`,
/// `opf:scheme`, `<meta name="calibre:series">`) and OPF 3 (`refines`,
/// `belongs-to-collection`) markup.
class OpfMetadata {
  OpfMetadata._();

  static BookMetadata parse(XmlDocument opf) {
    final metadata =
        opf.findAllElements('metadata', namespace: '*').firstOrNull;
    if (metadata == null) return const BookMetadata();

    Iterable<XmlElement> dc(String name) =>
        metadata.findAllElements(name, namespace: '*');
    final metas = metadata.findAllElements('meta', namespace: '*').toList();

    // OPF 3: <meta refines="#id" property="...">value</meta>
    final refinements = <String, List<XmlElement>>{};
    for (final meta in metas) {
      final target = meta.getAttribute('refines');
      if (target != null && target.startsWith('#')) {
        refinements.putIfAbsent(target.substring(1), () => []).add(meta);
      }
    }
    String? refined(XmlElement element, String property) {
      final id = element.getAttribute('id');
      if (id == null) return null;
      for (final meta in refinements[id] ?? const <XmlElement>[]) {
        if (meta.getAttribute('property') == property) {
          final value = _clean(meta.innerText);
          if (value.isNotEmpty) return value;
        }
      }
      return null;
    }

    // <meta name="x" content="y"/> (OPF 2) or <meta property="x">y</meta>.
    String? namedMeta(String name) {
      for (final meta in metas) {
        if (meta.getAttribute('name') == name) {
          final value = _clean(meta.getAttribute('content') ?? '');
          if (value.isNotEmpty) return value;
        }
      }
      for (final meta in metas) {
        if (meta.getAttribute('property') == name &&
            meta.getAttribute('refines') == null) {
          final value = _clean(meta.innerText);
          if (value.isNotEmpty) return value;
        }
      }
      return null;
    }

    // ---- title ----
    final titles = dc('title').where((t) => _clean(t.innerText).isNotEmpty);
    final mainTitle =
        titles.where((t) => refined(t, 'title-type') == 'main').firstOrNull ??
            titles.firstOrNull;
    final title = mainTitle == null ? '' : _clean(mainTitle.innerText);
    final titleSort = namedMeta('calibre:title_sort') ??
        (mainTitle == null
            ? null
            : refined(mainTitle, 'file-as') ?? _attr(mainTitle, 'file-as')) ??
        '';

    // ---- authors (creators with role "aut" or no role, as Calibre) ----
    final authors = <String>[];
    final authorSorts = <String>[];
    for (final creator in dc('creator')) {
      final role =
          (_attr(creator, 'role') ?? refined(creator, 'role') ?? '').trim();
      if (role.isNotEmpty && role.toLowerCase() != 'aut') continue;
      final names = Calibre.stringToAuthors(_clean(creator.innerText));
      if (names.isEmpty) continue;
      authors.addAll(names);
      final fileAs = _attr(creator, 'file-as') ?? refined(creator, 'file-as');
      if (fileAs != null && fileAs.trim().isNotEmpty) {
        authorSorts.add(fileAs.trim());
      }
    }
    final uniqueAuthors = _unique(authors);

    // ---- publication date ----
    DateTime? pubdate;
    for (final date in dc('date')) {
      final event = _attr(date, 'event')?.toLowerCase();
      if (event != null &&
          event != 'publication' &&
          event != 'original-publication') {
        continue;
      }
      pubdate = Calibre.parseDate(_clean(date.innerText));
      if (pubdate != null) break;
    }

    // ---- identifiers ----
    final identifiers = <String, String>{};
    for (final element in dc('identifier')) {
      final scheme = _attr(element, 'scheme') ??
          refined(element, 'identifier-type');
      final entry = Calibre.identifier(scheme, _clean(element.innerText));
      if (entry != null) identifiers.putIfAbsent(entry.key, () => entry.value);
    }

    // ---- series ----
    var series = namedMeta('calibre:series') ?? '';
    var seriesIndex = double.tryParse(namedMeta('calibre:series_index') ?? '');
    if (series.isEmpty) {
      for (final meta in metas) {
        if (meta.getAttribute('property') != 'belongs-to-collection') continue;
        final type = refined(meta, 'collection-type');
        if (type != null && type != 'series') continue;
        final name = _clean(meta.innerText);
        if (name.isEmpty) continue;
        series = name;
        seriesIndex = double.tryParse(refined(meta, 'group-position') ?? '');
        break;
      }
    }

    // ---- tags (Calibre splits subjects on commas) ----
    final tags = _unique([
      for (final subject in dc('subject'))
        ..._clean(subject.innerText).split(',').map((t) => t.trim()),
    ]);

    // ---- languages ----
    final languages = _unique([
      for (final language in dc('language'))
        Calibre.languageCode(_clean(language.innerText)) ?? '',
    ]);

    final rating = double.tryParse(namedMeta('calibre:rating') ?? '');

    return BookMetadata(
      title: title,
      titleSort: titleSort,
      authors: uniqueAuthors,
      authorSort: authorSorts.join(' & '),
      publisher: _first(dc('publisher')),
      pubdate: pubdate,
      description: dc('description')
              .map((d) => d.innerText.trim())
              .where((d) => d.isNotEmpty)
              .firstOrNull ??
          '',
      series: series,
      seriesIndex: series.isEmpty ? null : seriesIndex,
      tags: tags,
      languages: languages,
      identifiers: identifiers,
      rating: rating == null || rating <= 0
          ? null
          : rating.round().clamp(0, 10).toInt(),
    );
  }

  /// Attribute by local name, whatever its prefix (`opf:role`, `role`).
  static String? _attr(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _first(Iterable<XmlElement> elements) =>
      elements.map((e) => _clean(e.innerText)).where((t) => t.isNotEmpty).firstOrNull ??
      '';

  /// Drops blanks and case-insensitive duplicates, keeping the order.
  static List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final v in values)
        if (v.isNotEmpty && seen.add(v.toLowerCase())) v,
    ];
  }
}
