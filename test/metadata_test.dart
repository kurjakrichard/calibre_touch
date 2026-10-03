// Run with: flutter test test/metadata_test.dart
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:calibre_touch/metadata/metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

void main() {
  group('Calibre conventions', () {
    test('title sort', () {
      expect(Calibre.titleSort('A Crown of Ruin'), 'Crown of Ruin, A');
      expect(Calibre.titleSort('The Hobbit'), 'Hobbit, The');
      expect(Calibre.titleSort('Az ember tragédiája', languages: ['hun']),
          'ember tragédiája, Az');
      expect(Calibre.titleSort('Dune'), 'Dune');
    });

    test('author sort', () {
      expect(Calibre.authorSort('Jennifer L. Armentrout'),
          'Armentrout, Jennifer L.');
      expect(Calibre.authorSort('Martin Luther King Jr.'),
          'King, Martin Luther Jr.');
      expect(Calibre.authorSort('Homer'), 'Homer');
      expect(Calibre.authorSort('Dr. John Smith'), 'Smith, John');
    });

    test('authors from a string', () {
      expect(Calibre.stringToAuthors('Jane Doe & John Smith'),
          ['Jane Doe', 'John Smith']);
      expect(Calibre.stringToAuthors('Jane Doe and John Smith'),
          ['Jane Doe', 'John Smith']);
    });

    test('library paths (as Calibre names them)', () {
      expect(Calibre.bookFolder(1, 'A Crown of Ruin', 'Jennifer L. Armentrout'),
          'Jennifer L. Armentrout/A Crown of Ruin (1)');
      expect(
          Calibre.bookFileName(
              'A Crown of Ruin', 'Jennifer L. Armentrout', 'epub'),
          'A Crown of Ruin - Jennifer L. Armentrout');
      expect(Calibre.bookFolder(7, 'Mi: a kérdés?', 'Gárdonyi Géza'),
          'Gardonyi Geza/Mi_ a kerdes_ (7)');
    });

    test('languages and identifiers', () {
      expect(Calibre.languageCode('en'), 'eng');
      expect(Calibre.languageCode('hu-HU'), 'hun');
      expect(Calibre.languageCode('ger'), 'deu');
      expect(Calibre.languageCode('und'), isNull);
      expect(Calibre.identifier(null, 'urn:isbn:978-1-968707-65-1'),
          isA<MapEntry<String, String>>()
              .having((e) => e.key, 'key', 'isbn')
              .having((e) => e.value, 'value', '9781968707651'));
      expect(Calibre.identifier('MOBI-ASIN', 'B0GCPNLXDQ')?.key, 'mobi-asin');
      expect(Calibre.identifier('uuid', '1234'), isNull);
      expect(Calibre.identifier('ISBN', '1234567890'), isNull); // bad checksum
    });

    test('timestamps', () {
      expect(Calibre.formatTimestamp(DateTime.utc(2026, 10, 3, 13, 13, 37)),
          '2026-10-03 13:13:37+00:00');
      expect(
          Calibre.formatTimestamp(
              DateTime.utc(2026, 10, 3, 13, 13, 37, 697, 500)),
          '2026-10-03 13:13:37.697500+00:00');
    });
  });

  group('EPUB', () {
    test('OPF 3 metadata and cover', () {
      final metadata = parseEpubMetadata(_testEpub());
      expect(metadata.format, 'EPUB');
      expect(metadata.title, 'The Test Book');
      expect(metadata.titleSort, ''); // none in the file
      expect(metadata.authors, ['Jane Doe', 'John Smith']);
      expect(metadata.publisher, 'Test Press');
      expect(metadata.pubdate, DateTime(2020, 5, 17));
      expect(metadata.series, 'Test Saga');
      expect(metadata.seriesIndex, 2);
      expect(metadata.tags, ['Fantasy', 'Epic']);
      expect(metadata.languages, ['eng', 'hun']);
      expect(metadata.identifiers, {'isbn': '9781968707651'});
      expect(metadata.description, contains('<p>A <b>test</b> book.</p>'));
      expect(metadata.cover, isNotNull);
      expect(CoverImage.isJpeg(metadata.cover!), isTrue); // PNG converted
    });
  });

  group('PDF', () {
    test('/Info dictionary', () {
      final pdf = _pdf([
        '1 0 obj << /Type /Catalog >> endobj',
        // "Árva Lány" as UTF-16BE hex
        '3 0 obj << /Title <FEFF00C10072007600610020004C00E1006E0079> '
            '/Author (Jane Doe & John Smith) /Keywords (fantasy; epic) >> endobj',
      ], trailer: '/Root 1 0 R /Info 3 0 R');
      final metadata = parsePdfMetadata(pdf);
      expect(metadata.title, 'Árva Lány');
      expect(metadata.authors, ['Jane Doe', 'John Smith']);
      expect(metadata.tags, ['fantasy', 'epic']);
      expect(metadata.format, 'PDF');
    });

    test('XMP wins over /Info, Calibre series', () {
      const xmp = '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
          '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
          '<rdf:Description rdf:about="" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:calibre="http://calibre-ebook.com/xmp-namespace" '
          'xmlns:calibreSI="http://calibre-ebook.com/xmp-namespace-series-index">'
          '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">XMP Title</rdf:li>'
          '</rdf:Alt></dc:title>'
          '<dc:creator><rdf:Seq><rdf:li>Ann Author</rdf:li></rdf:Seq></dc:creator>'
          '<calibre:series rdf:parseType="Resource"><rdf:value>Saga</rdf:value>'
          '<calibreSI:series_index>2.00</calibreSI:series_index></calibre:series>'
          '</rdf:Description></rdf:RDF></x:xmpmeta>';
      final pdf = _pdf([
        '1 0 obj << /Type /Catalog /Metadata 4 0 R >> endobj',
        '3 0 obj << /Title (Info Title) /Author (Someone Else) >> endobj',
        '4 0 obj << /Type /Metadata /Subtype /XML /Length ${xmp.length} >>\n'
            'stream\n$xmp\nendstream endobj',
      ], trailer: '/Root 1 0 R /Info 3 0 R');
      final metadata = parsePdfMetadata(pdf);
      expect(metadata.title, 'XMP Title');
      expect(metadata.authors, ['Ann Author']);
      expect(metadata.series, 'Saga');
      expect(metadata.seriesIndex, 2);
    });

    test('/Info inside a compressed object stream (PDF 1.5+)', () {
      const objects = '<< /Title (Packed Title) /Author (Packer) >>';
      const header = '5 0 ';
      final packed = zlib.encode(latin1.encode('$header$objects'));
      final bytes = BytesBuilder()
        ..add(latin1.encode('%PDF-1.5\n1 0 obj << /Type /Catalog >> endobj\n'
            '6 0 obj << /Type /ObjStm /N 1 /First ${header.length} '
            '/Filter /FlateDecode /Length ${packed.length} >>\nstream\n'))
        ..add(packed)
        ..add(latin1.encode('\nendstream endobj\n'
            'trailer << /Root 1 0 R /Info 5 0 R >>\n%%EOF\n'));
      final metadata = parsePdfMetadata(bytes.toBytes());
      expect(metadata.title, 'Packed Title');
      expect(metadata.authors, ['Packer']);
    });

    test('file-name titles are ignored', () {
      final pdf = _pdf([
        '1 0 obj << /Type /Catalog >> endobj',
        '3 0 obj << /Title (Microsoft Word - thesis.docx) >> endobj',
      ], trailer: '/Root 1 0 R /Info 3 0 R');
      expect(parsePdfMetadata(pdf).title, '');
    });
  });

  test('metadata.opf round trip (OpfWriter -> OpfMetadata)', () {
    final xml = OpfWriter.write(const OpfBook(
      id: 1,
      uuid: '848a5fac-370e-403b-aed1-d5c2429564e6',
      title: 'A Crown of Ruin & <More>',
      titleSort: 'Crown of Ruin & <More>, A',
      authors: [OpfAuthor('Jennifer L. Armentrout', 'Armentrout, Jennifer L.')],
      timestamp: '2026-10-03 13:13:37.697500+00:00',
      pubdate: '2025-12-25 23:00:00+00:00',
      publisher: 'Blue Box Press',
      description: '<div><p>Blurb</p></div>',
      series: 'Blood and Ash',
      seriesIndex: 6.5,
      rating: 8,
      tags: ['Fantasy', 'Romance'],
      languages: ['eng'],
      identifiers: {'isbn': '9781968707651', 'goodreads': '245804344'},
      hasCover: true,
    ));
    expect(xml, contains('<dc:identifier opf:scheme="calibre" id="calibre_id">1'));
    expect(xml, contains('<reference type="cover" title="Cover" href="cover.jpg"/>'));
    expect(xml, contains('content="2026-10-03T13:13:37.697500+00:00"'));

    final m = OpfMetadata.parse(XmlDocument.parse(xml));
    expect(m.title, 'A Crown of Ruin & <More>');
    expect(m.titleSort, 'Crown of Ruin & <More>, A');
    expect(m.authors, ['Jennifer L. Armentrout']);
    expect(m.authorSort, 'Armentrout, Jennifer L.');
    expect(m.pubdate, DateTime.utc(2025, 12, 25, 23));
    expect(m.publisher, 'Blue Box Press');
    expect(m.description, '<div><p>Blurb</p></div>');
    expect(m.series, 'Blood and Ash');
    expect(m.seriesIndex, 6.5);
    expect(m.rating, 8);
    expect(m.tags, ['Fantasy', 'Romance']);
    expect(m.languages, ['eng']);
    expect(m.identifiers, {'isbn': '9781968707651', 'goodreads': '245804344'});
  });

  test('file name fallback', () {
    final m = BookMetadata.fromFileName(
        '/x/A_crown_of_ruin_-_Jennifer_L_Armentrout.epub');
    expect(m.title, 'A crown of ruin');
    expect(m.authors, ['Jennifer L Armentrout']);
    expect(m.format, 'EPUB');
  });
}

Uint8List _pdf(List<String> objects, {required String trailer}) =>
    Uint8List.fromList(latin1.encode('%PDF-1.4\n${objects.join('\n')}\n'
        'trailer << $trailer >>\n%%EOF\n'));

Uint8List _testEpub() {
  const container = '<?xml version="1.0"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opf = '''
  <?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:uuid:12345678-1234-1234-1234-123456789012</dc:identifier>
    <dc:identifier>urn:isbn:9781968707651</dc:identifier>
    <dc:title id="t1">The Test Book</dc:title>
    <meta refines="#t1" property="title-type">main</meta>
    <dc:creator id="c1">Jane Doe</dc:creator>
    <meta refines="#c1" property="role" scheme="marc:relators">aut</meta>
    <dc:creator id="c2">John Smith</dc:creator>
    <dc:creator id="c3">Ed Itor</dc:creator>
    <meta refines="#c3" property="role" scheme="marc:relators">edt</meta>
    <dc:publisher>Test Press</dc:publisher>
    <dc:date>2020-05-17</dc:date>
    <dc:subject>Fantasy, Epic</dc:subject>
    <dc:language>en-US</dc:language>
    <dc:language>hu</dc:language>
    <dc:description>&lt;p&gt;A &lt;b&gt;test&lt;/b&gt; book.&lt;/p&gt;</dc:description>
    <meta property="belongs-to-collection" id="s1">Test Saga</meta>
    <meta refines="#s1" property="collection-type">series</meta>
    <meta refines="#s1" property="group-position">2</meta>
  </metadata>
  <manifest>
    <item id="cov" href="images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''';
  final png = img.encodePng(img.Image(width: 4, height: 6, numChannels: 4));
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(ArchiveFile.string('META-INF/container.xml', container))
    ..addFile(ArchiveFile.string('OEBPS/content.opf', opf))
    ..addFile(ArchiveFile.string(
        'OEBPS/ch1.xhtml', '<html><body><p>Hello</p></body></html>'))
    ..addFile(ArchiveFile.bytes('OEBPS/images/cover.png', png));
  return ZipEncoder().encodeBytes(archive);
}
