import 'dart:typed_data';

import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';
import 'package:dart_mobi/src/dart_mobi_encryption.dart';
import 'package:dart_mobi/src/dart_mobi_exception.dart';
import 'package:dart_mobi/src/dart_mobi_reader.dart';
import 'package:dart_mobi/src/dart_mobi_utils.dart';

class CompressionUtils {
  static Uint8List decompressContent(MobiData data) {
    if (EncryptionUtils.isEncrypted(data) && !EncryptionUtils.hasDrmKey(data)) {
      throw MobiFileEncryptedException();
    }
    // Calibre Touch: BytesBuilder instead of `res + decompressed` per record
    // (quadratic copying on big books).
    final res = BytesBuilder(copy: false);

    int offset = getKf8Offset(data);
    if (data.record0header == null ||
        data.record0header!.textRecordCount! == 0) {
      throw MobiInvalidDataException("Text Record not Found");
    }
    final textRecIndex = 1 + offset;
    var textRecCount = data.record0header!.textRecordCount!;
    var compressionType = data.record0header!.compressionType!;
    int extraFlags = 0;
    if (data.mobiHeader != null && data.mobiHeader!.extraFlags != null) {
      extraFlags = data.mobiHeader!.extraFlags!;
    }
    var curr =
        DartMobiReader.getRecordBySeqNumber(data.mobiPdbRecord!, textRecIndex);
    var huffcdic = MobiHuffCdic();
    if (compressionType == compressionHuffCdic) {
      parseHuffdic(data, huffcdic);
    }
    while (textRecCount-- != 0 && curr != null) {
      int extraSize = 0;
      if (extraFlags != 0) {
        extraSize = getRecordExtraSize(curr, extraFlags);
        if (extraSize == mobiNotSet) {
          throw MobiInvalidDataException("Extra Size Invalid");
        }
      }
      int decompressedSize = getMaxTextRecordSize(data);
      if (EncryptionUtils.isEncrypted(data) &&
          EncryptionUtils.hasDrmKey(data)) {
        int extraSize = getRecordExtraSize(curr, extraFlags & 0xfffe);
        if (extraSize == mobiNotSet || extraSize > curr.size!) {
          throw MobiInvalidDataException("Encryption Extra Size Invalid");
        }
        final decryptSize = curr.size! - extraSize;
        if (decryptSize > decompressedSize && decryptSize > curr.size!) {
          throw MobiInvalidDataException("Record too Large $decryptSize");
        }
        if (decryptSize != 0) {
          curr.data = Uint8List.fromList(
              EncryptionUtils.decryptBuffer(curr.data!, data, decryptSize));
        }

        if (compressionType != compressionHuffCdic && (extraFlags & 1) != 0) {
          extraSize = getRecordExtraSize(curr, extraFlags);
        }
      }
      if (extraSize > curr.size!) {
        throw MobiInvalidDataException(
            "Wrong Record Size ${extraSize - curr.size!}");
      }
      if (extraSize == curr.size) {
        curr = curr.next;
        continue;
      }
      Uint8List decompressed;
      final recordSize = curr.size! - extraSize;
      switch (compressionType) {
        case compressionNone:
          if (recordSize > decompressedSize) {
            throw MobiInvalidDataException("Record too Large $recordSize");
          }

          decompressed = curr.data!;
          decompressedSize = recordSize;
          if (data.mobiHeader != null && getFileVersion(data) <= 3) {
            decompressedSize = removeZeros(decompressed);
          }
        case compressionPalmDoc:
          final out = decompressLz77(
              curr.data!.sublist(0, recordSize), decompressedSize);
          decompressedSize = out.offset;
          decompressed = out.data;
        case compressionHuffCdic:
          // Calibre Touch: without the trailing entries (like libmobi).
          final out = decompressHuffman(
              Uint8List.sublistView(curr.data!, 0, recordSize),
              decompressedSize,
              huffcdic);
          decompressedSize = out.offset;
          decompressed = out.data;
        default:
          throw MobiInvalidDataException("Unknown Compression Type");
      }
      curr = curr.next;
      // Calibre Touch: only the decompressed bytes. 1.0.2 appended the whole
      // 4096-byte output buffer (NULs after a short last record) and, for
      // uncompressed text, the record's trailing entries too.
      res.add(Uint8List.sublistView(decompressed, 0, decompressedSize));
    }
    return res.toBytes();
  }

  // Calibre Touch: HUFF/CDIC rewritten after libmobi (huffcdic.c,
  // mobi_parse_huff / mobi_parse_cdic / mobi_decompress_huffman). 1.0.2
  // could never read these books: the CDIC null check and magic check were
  // inverted, table1 was read from the data2 offset, `symbols` was an empty
  // list, maxcode had an operator precedence error, the recursion swapped
  // its input and output buffers and addRaw wrote into its argument.

  static void parseHuffdic(MobiData data, MobiHuffCdic huffcdic) {
    final offset = getKf8Offset(data);
    final index = data.mobiHeader?.huffRecordIndex;
    final count = data.mobiHeader?.huffRecordCount;
    if (index == null || count == null || index == mobiNotSet) {
      throw MobiInvalidDataException("HUFF/CDIC Record Metadata not Found");
    }
    var curr =
        DartMobiReader.getRecordBySeqNumber(data.mobiPdbRecord!, index + offset);
    if (curr == null || count < 2 || count > 255) {
      throw MobiInvalidDataException("HUFF/CDIC record not Found");
    }
    parseHuff(huffcdic, curr);
    for (int i = 0; i < count - 1; i++) {
      curr = curr?.next;
      if (curr == null) {
        throw MobiInvalidDataException("CDIC record not Found");
      }
      parseCdic(huffcdic, curr, i);
    }
    if (huffcdic.indexCount != huffcdic.indexRead) {
      throw MobiInvalidDataException(
          "CDIC Wrong Read Index Count: ${huffcdic.indexRead}, Total: ${huffcdic.indexCount}");
    }
  }

  static void parseHuff(MobiHuffCdic huffcdic, MobiPdbRecord record) {
    final buffer = MobiBuffer(record.data!, 0);
    final magic = buffer.getString(4);
    final headerLength = buffer.getInt32();
    if (magic != huffMagic || headerLength < huffHeaderLen) {
      throw MobiInvalidDataException("Invalid HUFF Header");
    }
    final data1Offset = buffer.getInt32();
    final data2Offset = buffer.getInt32();

    // table1: 256 entries indexed by the next 8 bits of the code.
    buffer.setPos(data1Offset);
    if (buffer.offset + 256 * 4 > buffer.maxlen) {
      throw MobiInvalidDataException("HUFF data1 too Short");
    }
    for (int i = 0; i < 256; i++) {
      huffcdic.table1[i] = buffer.getInt32();
    }

    // Min/max code of every code length 1..32, left-aligned to 32 bits.
    buffer.setPos(data2Offset);
    if (buffer.offset + 64 * 4 > buffer.maxlen) {
      throw MobiInvalidDataException("HUFF data2 too short");
    }
    huffcdic.minCodeTable[0] = 0;
    huffcdic.maxCodeTable[0] = 0xFFFFFFFF;
    for (int i = 1; i < huffCodeTableSize; i++) {
      final minCode = buffer.getInt32();
      final maxCode = buffer.getInt32();
      huffcdic.minCodeTable[i] = (minCode << (32 - i)) & 0xFFFFFFFF;
      huffcdic.maxCodeTable[i] = (((maxCode + 1) << (32 - i)) - 1) & 0xFFFFFFFF;
    }
  }

  static void parseCdic(MobiHuffCdic huffcdic, MobiPdbRecord record, int n) {
    final buffer = MobiBuffer(record.data!, 0);
    final magic = buffer.getString(4);
    final headerLength = buffer.getInt32();
    if (magic != cdicMagic || headerLength < cdicHeaderLen) {
      throw MobiInvalidDataException(
          "CDIC wrong magic $magic or Header too Short");
    }
    var indexCount = buffer.getInt32();
    final codeLength = buffer.getInt32();
    if (huffcdic.codeLength != 0 && huffcdic.codeLength != codeLength) {
      throw MobiInvalidDataException(
          "CDIC code length in record is $codeLength, but previously was ${huffcdic.codeLength}");
    }
    if (huffcdic.indexCount != 0 && huffcdic.indexCount != indexCount) {
      throw MobiInvalidDataException(
          "CDIC index count in record is $indexCount, but previously was ${huffcdic.indexCount}");
    }
    if (codeLength == 0 || codeLength > huffCodeLenMax) {
      throw MobiInvalidDataException(
          "Code Length Exceeds Max Code Length: $codeLength");
    }
    if (indexCount == 0) {
      throw MobiInvalidDataException("CDIC Index Count is Null");
    }
    huffcdic.codeLength = codeLength;
    huffcdic.indexCount = indexCount;
    if (n == 0) {
      huffcdic.symbolOffsets = List.filled(indexCount, 0);
    }

    // This record holds at most 2^codeLength of the remaining symbols.
    indexCount -= huffcdic.indexRead;
    if ((indexCount >> codeLength) != 0) {
      indexCount = 1 << codeLength;
    }
    if (buffer.offset + indexCount * 2 > buffer.maxlen) {
      throw MobiInvalidDataException("CDIC Indices Data Too Short");
    }
    while (indexCount-- > 0) {
      // Symbol offsets are relative to the end of the CDIC header.
      final offset = buffer.getInt16();
      final symbolStart = cdicHeaderLen + offset;
      if (symbolStart + 2 > buffer.maxlen) {
        throw MobiInvalidDataException("CDIC Offset Beyond Buffer");
      }
      final len = (record.data![symbolStart] << 8 |
              record.data![symbolStart + 1]) &
          0x7fff;
      if (symbolStart + 2 + len > buffer.maxlen) {
        throw MobiInvalidDataException("CDIC Offset Beyond Buffer");
      }
      huffcdic.symbolOffsets[huffcdic.indexRead++] = offset;
    }
    huffcdic.symbols.add(Uint8List.sublistView(record.data!, cdicHeaderLen));
  }

  static MobiBuffer decompressLz77(Uint8List data, int decompressedSize) {
    final buffer = MobiBuffer(data, 0);
    final outBuffer =
        MobiBuffer(Uint8List.fromList(List.filled(decompressedSize, 0)), 0);
    while (buffer.offset < buffer.maxlen) {
      var byte = buffer.getInt8();
      if (byte >= 0xc0) {
        outBuffer.add8(32);
        outBuffer.add8(byte ^ 0x80);
      } else if (byte >= 0x80) {
        int next = buffer.getInt8();
        int distance = (((byte << 8) | next) >> 3) & 0x7ff;
        int length = (next & 0x7) + 3;
        while (length-- != 0) {
          outBuffer.move(-distance, 1);
        }
      } else if (byte >= 0x09) {
        outBuffer.add8(byte);
      } else if (byte >= 0x01) {
        buffer.copy(outBuffer, byte);
      } else {
        // Calibre Touch: 0x00 is a literal NUL in the output. 1.0.2 wrote it
        // into the input buffer (overwriting and skipping the next input
        // byte), which garbled the text.
        outBuffer.add8(byte);
      }
    }
    return outBuffer;
  }

  static MobiBuffer decompressHuffman(
      Uint8List data, int decompressedSize, MobiHuffCdic huffcdic) {
    final outBuffer = MobiBuffer(Uint8List(decompressedSize), 0);
    decompressHuffmanInternal(MobiBuffer(data, 0), outBuffer, huffcdic, 0);
    return outBuffer;
  }

  static void decompressHuffmanInternal(
      MobiBuffer inBuf, MobiBuffer outBuf, MobiHuffCdic huffcdic, int depth) {
    if (depth > huffmanMaxDepth) {
      throw MobiInvalidDataException("Too Many Levels of Recursion");
    }
    int bitcount = 32;
    int bitsLeft = (inBuf.maxlen - inBuf.offset) * 8;
    int buffer = inBuf.fillInt64();
    while (true) {
      if (bitcount <= 0) {
        bitcount += 32;
        buffer = inBuf.fillInt64();
      }
      final code = (buffer >>> bitcount) & 0xFFFFFFFF;
      final t1 = huffcdic.table1[code >>> 24];
      int codeLength = t1 & 0x1f;
      int maxCode = ((((t1 >>> 8) + 1) << (32 - codeLength)) - 1) & 0xFFFFFFFF;
      if ((t1 & 0x80) == 0) {
        while (code < huffcdic.minCodeTable[codeLength]) {
          if (++codeLength >= huffCodeTableSize) {
            throw MobiInvalidDataException(
                "Wrong Offset to Mincode Table: $codeLength");
          }
        }
        maxCode = huffcdic.maxCodeTable[codeLength];
      }
      if (codeLength == 0) {
        throw MobiInvalidDataException("Invalid Huffman Code Length");
      }
      bitcount -= codeLength;
      bitsLeft -= codeLength;
      if (bitsLeft < 0) {
        break;
      }
      final index = ((maxCode - code) & 0xFFFFFFFF) >>> (32 - codeLength);
      if (index >= huffcdic.indexCount) {
        throw MobiInvalidDataException("Wrong Symbol Offsets Index: $index");
      }
      final cdicIndex = index >>> huffcdic.codeLength;
      if (cdicIndex >= huffcdic.symbols.length) {
        throw MobiInvalidDataException("Wrong CDIC Index: $cdicIndex");
      }
      final symbols = huffcdic.symbols[cdicIndex];
      final offset = huffcdic.symbolOffsets[index];
      if (offset + 2 > symbols.length) {
        throw MobiInvalidDataException("Symbol Offset Beyond Buffer");
      }
      var symbolLength = symbols[offset] << 8 | symbols[offset + 1];
      final isDecompressed = symbolLength >> 15 != 0;
      symbolLength &= 0x7fff;
      if (offset + 2 + symbolLength > symbols.length) {
        throw MobiInvalidDataException("Symbol Beyond Buffer");
      }
      final symbol =
          Uint8List.sublistView(symbols, offset + 2, offset + 2 + symbolLength);
      if (isDecompressed) {
        outBuf.addRaw(symbol, symbolLength);
      } else {
        // The symbol is itself Huffman-coded.
        decompressHuffmanInternal(
            MobiBuffer(symbol, 0), outBuf, huffcdic, depth + 1);
      }
    }
  }

  static int getRecordExtraSize(MobiPdbRecord record, int flags) {
    int extraSize = 0;
    final buffer = MobiBuffer(record.data!, 0);
    buffer.setPos(buffer.maxlen - 1);
    for (int bit = 15; bit > 0; bit--) {
      if ((flags & (1 << bit)) != 0) {
        int len = 0;
        int size = 0;
        (len, size) = buffer.getVarLen(len, backward: true);
        buffer.seek(-(size - len));
        extraSize += size;
      }
    }
    if ((flags & 1) != 0) {
      final b = buffer.getInt8();
      extraSize += (b & 0x3) + 1;
    }
    return extraSize;
  }
}

class MobiHuffCdic {
  int indexCount = 0;
  int indexRead = 0;
  int codeLength = 0;
  List<int> table1 = List.filled(256, 0);
  List<int> minCodeTable = List.filled(huffCodeTableSize, 0);
  List<int> maxCodeTable = List.filled(huffCodeTableSize, 0);
  List<int> symbolOffsets = [];
  List<Uint8List> symbols = [];
}
