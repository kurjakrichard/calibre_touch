import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:dart_mobi/dart_mobi.dart';

/// A MOBI / AZW / AZW3 (KF8) file opened with `dart_mobi`, plus the bits
/// the package doesn't do for us: EXTH metadata by tag, text in the book's
/// encoding (UTF-8 or CP1252), resource (image) records by index.
///
/// Shared by [MobiMetadataReader] and the reader's `MobiDocument`. Pure
/// Dart - use it inside an isolate.
///
/// For hybrid files (KF7 + KF8 in one .mobi, what kindlegen and Calibre
/// write) `dart_mobi` switches to the KF8 part; [useKf7] switches back.
class MobiFile {
  MobiFile._(this.data, this.records);

  /// `dart_mobi`'s parsed file.
  final MobiData data;

  /// Every PDB record, by record number.
  final List<MobiPdbRecord> records;

  static const int notSet = 0xffffffff;

  // EXTH record types (https://wiki.mobileread.com/wiki/MOBI#EXTH_Header).
  static const int exthAuthor = 100;
  static const int exthPublisher = 101;
  static const int exthDescription = 103;
  static const int exthIsbn = 104;
  static const int exthSubject = 105;
  static const int exthPublishingDate = 106;
  static const int exthAsin = 113;
  static const int exthCoverOffset = 201;
  static const int exthThumbOffset = 202;
  static const int exthUpdatedTitle = 503;
  static const int exthTitleFileAs = 508;
  static const int exthCreatorFileAs = 517;
  static const int exthLanguage = 524;

  /// Parses [bytes]. Throws if this is not a MOBI/PalmDOC file.
  static Future<MobiFile> parse(Uint8List bytes) async {
    final data = await DartMobiReader.read(bytes);
    final records = <MobiPdbRecord>[];
    for (MobiPdbRecord? r = data.mobiPdbRecord; r != null; r = r.next) {
      records.add(r);
    }
    await _repairHeaders(data, records);
    return MobiFile._(data, records);
  }

  // ---- MOBI header workaround ----
  //
  // dart_mobi 1.0.2's `readMobiHeader` always reads a full 264-byte (KF8)
  // MOBI header, but limits its buffer to the real header length. MOBI 6
  // headers (Calibre's and kindlegen's .mobi, the KF7 part of hybrids)
  // are 232 bytes, so it hits a MobiBufferOverflowException at offset 248,
  // which `readRecord0Header` silently swallows: no MOBI header, no EXTH.
  // Without the header the text records' trailing bytes are not stripped
  // (extraFlags = 0), and PalmDOC decompression overflows its 4096-byte
  // buffer -> "Buffer Overflow". Without EXTH hybrids aren't detected and
  // the metadata is lost. Here such headers are read again, honouring the
  // header length (like libmobi), and the hybrid check is redone.

  static const int _mobiHeaderOffset = 16;

  static Future<void> _repairHeaders(
      MobiData data, List<MobiPdbRecord> records) async {
    if (data.mobiHeader != null || records.isEmpty) return;
    if (!await _readHeaders(data, records.first.data)) return;

    if ((data.record0header?.encryptionType ?? 0) == 1) {
      // Same as DartMobiReader.read; it ran without a header the first time.
      try {
        EncryptionUtils.setDrmKey(data, null);
      } catch (_) {}
    }

    // Hybrid KF7 + KF8 file: DartMobiReader.read skipped this (no EXTH).
    if (data.next != null) return;
    final boundary = DartMobiReader.getKf8BoundarySeqNumber(data);
    if (boundary == notSet || boundary + 1 >= records.length) return;
    final kf8 = MobiData()
      ..pdbHeader = data.pdbHeader
      ..mobiPdbRecord = data.mobiPdbRecord
      ..drm = data.drm
      ..next = data;
    kf8.record0header = await DartMobiReader.readRecord0Header(
        kf8, data.mobiPdbRecord!, boundary + 1);
    if (kf8.mobiHeader == null) {
      await _readHeaders(kf8, records[boundary + 1].data);
    }
    data
      ..kf8BoundaryOffset = boundary
      ..next = kf8;
    if (data.kf8) {
      // Switch to the KF8 part (dart_mobi's swapMobiData).
      final record0header = data.record0header;
      final mobiHeader = data.mobiHeader;
      final exth = data.mobiExthHeader;
      data
        ..record0header = kf8.record0header
        ..mobiHeader = kf8.mobiHeader
        ..mobiExthHeader = kf8.mobiExthHeader;
      kf8
        ..record0header = record0header
        ..mobiHeader = mobiHeader
        ..mobiExthHeader = exth;
    }
  }

  /// Reads the MOBI header and the EXTH records of [record0] into [data].
  /// False if there is no readable MOBI header.
  static Future<bool> _readHeaders(MobiData data, Uint8List? record0) async {
    if (record0 == null) return false;
    final header = _readMobiHeader(record0);
    if (header == null) return false;
    data.mobiHeader = header;
    final exthOffset = _mobiHeaderOffset + header.headerSize!;
    if (exthOffset + 12 <= record0.length &&
        String.fromCharCodes(record0, exthOffset, exthOffset + 4) == 'EXTH') {
      try {
        data.mobiExthHeader =
            await DartMobiReader.readExthHeader(MobiBuffer(record0, exthOffset));
      } catch (_) {
        // Metadata only - the text can still be read.
      }
    }
    return true;
  }

  /// The MOBI header in [record0] (libmobi's `mobi_load_mh`): only fields
  /// inside the header's own length are read, the rest are "not set".
  static MobiHeader? _readMobiHeader(Uint8List record0) {
    const start = _mobiHeaderOffset;
    if (record0.length < start + 8 ||
        String.fromCharCodes(record0, start, start + 4) != 'MOBI') {
      return null;
    }
    int u32At(int offset) =>
        record0[offset] << 24 |
        record0[offset + 1] << 16 |
        record0[offset + 2] << 8 |
        record0[offset + 3];
    var headerSize = u32At(start + 4);
    if (headerSize == 0) headerSize = 24;
    // Fields after this record-0 offset are not in the header.
    final end = min(start + headerSize, record0.length);
    int? u32(int offset, [int? missing = notSet]) =>
        offset + 4 <= end ? u32At(offset) : missing;
    int? u16(int offset, [int? missing = 0xFFFF]) =>
        offset + 2 <= end ? record0[offset] << 8 | record0[offset + 1] : missing;

    final MobiEncoding encoding;
    try {
      encoding = MobiEncoding.fromValue(u32(28, 1252)!);
    } on StateError {
      return null; // dart_mobi: "Invalid Encoding in Mobi Header"
    }
    final version = u32(36, 1)!;
    final isKf8 = headerSize >= 0xe4 && version == 8;

    final h = MobiHeader()
      ..magic = 'MOBI'
      ..headerSize = headerSize
      ..mobiType = u32(24)
      ..encoding = encoding
      ..uid = u32(32)
      ..version = version
      ..orthographicIndex = u32(40)
      ..inflectionIndex = u32(44)
      ..namesIndex = u32(48)
      ..keysIndex = u32(52)
      ..extra0Index = u32(56)
      ..extra1Index = u32(60)
      ..extra2Index = u32(64)
      ..extra3Index = u32(68)
      ..extra4Index = u32(72)
      ..extra5Index = u32(76)
      ..nonTextIndex = u32(80)
      ..fullNameOffset = u32(84, 0)
      ..fullNameLength = u32(88, 0)
      ..locale = u32(92, 0)
      ..dictInputLang = u32(96, 0)
      ..dictOutputLang = u32(100, 0)
      ..minVersion = u32(104, 0)
      ..imageIndex = u32(108)
      ..huffRecordIndex = u32(112)
      ..huffRecordCount = u32(116, 0)
      ..datpRecordIndex = u32(120)
      ..datpRecordCount = u32(124, 0)
      ..exthFlags = u32(128, 0)
      ..unknown6 = u32(164)
      ..drmOffset = u32(168)
      ..drmCount = u32(172, 0)
      ..drmSize = u32(176, 0)
      ..drmFlags = u32(180, 0)
      ..fdstSectionCount = u32(196, 0)
      ..fcisIndex = u32(200)
      ..fcisCount = u32(204, 0)
      ..flisIndex = u32(208)
      ..flisCount = u32(212, 0)
      ..unknown10 = u32(216)
      ..unknown11 = u32(220)
      ..srcsIndex = u32(224)
      ..srcsCount = u32(228, 0)
      ..unknown12 = u32(232)
      ..unknown13 = u32(236)
      ..extraFlags = u16(242, 0)
      ..ncxIndex = u32(244)
      ..datpIndex = u32(256)
      ..unknown17 = u32(264)
      ..unknown18 = u32(268)
      ..unknown19 = u32(272)
      ..unknown20 = u32(276);
    if (isKf8) {
      h
        ..fdstIndex = u32(192)
        ..fragmentIndex = u32(248)
        ..skeletonIndex = u32(252)
        ..guideIndex = u32(260);
    } else {
      h
        ..firstTextIndex = u16(192)
        ..lastTextIndex = u16(194)
        ..unknown14 = u32(248)
        ..unknown15 = u32(252)
        ..unknown16 = u32(260);
    }

    final nameOffset = h.fullNameOffset!;
    final nameLength = min(h.fullNameLength!, 1024);
    if (nameOffset != 0 &&
        nameLength != 0 &&
        nameOffset + nameLength <= record0.length) {
      h.fullname =
          String.fromCharCodes(record0, nameOffset, nameOffset + nameLength);
    }
    return h;
  }

  /// True for KF8 (AZW3, or the KF8 part of a hybrid .mobi).
  bool get isKf8 => (data.mobiHeader?.version ?? 0) >= 8;

  /// True if the file has both a KF7 and a KF8 part.
  bool get isHybrid => data.kf8BoundaryOffset != notSet && data.next != null;

  /// Added to KF8 header record numbers (indexes, FDST): the KF8 part of
  /// a hybrid file starts after its BOUNDARY record. 0 otherwise.
  int get kf8Offset => isHybrid && data.kf8 ? data.kf8BoundaryOffset + 1 : 0;

  /// Switches a hybrid file back to its old KF7 (MOBI 6) part - used when
  /// the KF8 part can't be read. Same as libmobi's "-7" option.
  void useKf7() {
    final other = data.next;
    if (!isHybrid || !data.kf8 || other == null) return;
    final record0header = data.record0header;
    final mobiHeader = data.mobiHeader;
    final exth = data.mobiExthHeader;
    data
      ..record0header = other.record0header
      ..mobiHeader = other.mobiHeader
      ..mobiExthHeader = other.mobiExthHeader
      ..kf8 = false;
    other
      ..record0header = record0header
      ..mobiHeader = mobiHeader
      ..mobiExthHeader = exth;
  }

  /// DRM-protected (bought from Amazon, ...). Metadata is still readable,
  /// the text is not. (Old "V1" encryption has no real key - `dart_mobi`
  /// decrypts that one.)
  bool get isEncrypted =>
      (data.record0header?.encryptionType ?? 0) == 2 ||
      ((data.record0header?.encryptionType ?? 0) == 1 && data.drm?.key == null);

  /// True if text is CP1252 (old MOBI files), false for UTF-8.
  bool get isCp1252 => data.mobiHeader?.encoding == MobiEncoding.CP1252;

  /// Decodes [bytes] in the book's encoding. Never throws.
  String decode(List<int> bytes) =>
      isCp1252 ? decodeCp1252(bytes) : utf8.decode(bytes, allowMalformed: true);

  /// Windows-1252 -> String (latin1 except 0x80-0x9F).
  static String decodeCp1252(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      if (b >= 0x80 && b < 0xA0) {
        out.writeCharCode(_cp1252High[b - 0x80]);
      } else {
        out.writeCharCode(b);
      }
    }
    return out.toString();
  }

  static const List<int> _cp1252High = [
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
    0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
  ];

  // ---- EXTH ----

  /// The raw values of every EXTH record of [tag], in file order.
  List<Uint8List> exth(int tag) {
    final values = <Uint8List>[];
    for (MobiExthHeader? e = data.mobiExthHeader; e != null; e = e.next) {
      final value = e.data;
      if (e.tag == tag && value != null) values.add(value);
    }
    return values;
  }

  /// Text values of EXTH [tag] (trimmed, empty ones dropped).
  List<String> exthStrings(int tag) => [
        for (final value in exth(tag))
          if (decode(value).trim().isNotEmpty) decode(value).trim(),
      ];

  /// First text value of EXTH [tag], or ''.
  String exthString(int tag) {
    final values = exthStrings(tag);
    return values.isEmpty ? '' : values.first;
  }

  /// First EXTH [tag] read as a big-endian number (1-4 bytes), or null.
  int? exthInt(int tag) {
    for (final value in exth(tag)) {
      if (value.isEmpty || value.length > 4) continue;
      var n = 0;
      for (final b in value) {
        n = (n << 8) | b;
      }
      return n;
    }
    return null;
  }

  /// The title in record 0 ("full name"), decoded in the book's encoding.
  String get fullName {
    // dart_mobi turns the bytes into chars one by one (latin1); turn them
    // back into bytes to decode UTF-8 titles properly.
    final raw = data.mobiHeader?.fullname;
    if (raw == null || raw.isEmpty) return '';
    final codes = raw.codeUnits;
    if (codes.any((c) => c > 0xFF)) return raw.trim(); // already decoded
    return decode(codes).replaceAll('\u0000', '').trim();
  }

  /// The database name in the PDB header (title, often shortened).
  String get pdbName =>
      (data.pdbHeader?.name ?? '').replaceAll('\u0000', '').trim();

  // ---- resources (images) ----

  /// Record number of the first resource (image) record, or null. For
  /// hybrid files the resources are shared and listed by the KF7 header.
  int? get firstResourceRecord {
    int? index;
    if (isHybrid && data.kf8) index = data.next?.mobiHeader?.imageIndex;
    index ??= data.mobiHeader?.imageIndex;
    if (index == null || index == notSet || index >= records.length) {
      return null;
    }
    return index;
  }

  /// Resource number [n] (0-based: `recindex="00001"` and
  /// `kindle:embed:0001` are n = 0). Null if missing.
  Uint8List? resource(int n) {
    final first = firstResourceRecord;
    if (first == null || n < 0) return null;
    final index = first + n;
    if (index >= records.length) return null;
    return records[index].data;
  }

  /// [resource] [n] if it is a JPEG/PNG/GIF/BMP/WebP image.
  Uint8List? image(int n) {
    final bytes = resource(n);
    return bytes != null && isImage(bytes) ? bytes : null;
  }

  static bool isImage(Uint8List b) {
    if (b.length < 4) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true; // PNG
    }
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    if (b[0] == 0x42 && b[1] == 0x4D) return true; // BMP
    return b.length > 11 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50; // WebP
  }

  /// The cover image (EXTH cover offset, else the thumbnail), or null.
  Uint8List? get cover {
    for (final tag in const [exthCoverOffset, exthThumbOffset]) {
      final offset = exthInt(tag);
      if (offset == null || offset == notSet) continue;
      final bytes = image(offset);
      if (bytes != null) return bytes;
    }
    return null;
  }

  /// Number of the base-32 digits used by KF8 links (`kindle:embed:000A`,
  /// `kindle:pos:fid:0001`): 0-9 then A-V.
  static int? base32(String digits) {
    var n = 0;
    for (final c in digits.toUpperCase().codeUnits) {
      final int v;
      if (c >= 0x30 && c <= 0x39) {
        v = c - 0x30;
      } else if (c >= 0x41 && c <= 0x56) {
        v = c - 0x41 + 10;
      } else {
        return null;
      }
      n = n * 32 + v;
    }
    return n;
  }
}
