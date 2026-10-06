## 1.0.2+calibretouch.1

Vendored copy of dart_mobi 1.0.2 (https://pub.dev/packages/dart_mobi,
LGPL-3.0, see LICENSE), modified for Calibre Touch:

- `CompressionUtils.decompressLz77`: control byte 0x00 now writes a NUL to
  the output. 1.0.2 wrote it into the input buffer, overwriting and skipping
  the next compressed byte, which garbled PalmDOC text.
- `DartMobiReader.readMobiHeader`: fields beyond the header's own length are
  "not set" instead of throwing MobiBufferOverflowException. 1.0.2 always
  read a 264-byte (KF8) header, so every 232-byte MOBI 6 header (Calibre /
  kindlegen .mobi, KF7 part of hybrids) failed: the exception was swallowed,
  the MOBI header and EXTH were lost, and text decompression then failed
  with "Buffer Overflow".
- `DartMobiReader.readRecord0Header`: EXTH is read only if its magic is
  there; `readExthHeader` compared `exthMagic` with itself.
- `CompressionUtils.decompressContent`: appends only the decompressed bytes
  of each record (1.0.2 appended the whole 4096-byte buffer, so a short last
  record added NULs), using a BytesBuilder instead of quadratic copying.
- HUFF/CDIC decompression rewritten after libmobi (`parseHuffdic`,
  `parseHuff`, `parseCdic`, `decompressHuffman`). 1.0.2 could never open
  these books: the CDIC record null check and magic check were inverted,
  table1 was read from the data2 offset, `symbols` was an empty list,
  symbol lengths were read without the CDIC header offset, `maxCode` had an
  operator precedence error, the recursion swapped its input and output
  buffers, and whole records (with trailing entries) were decoded.
- `MobiBuffer.addRaw` appends to the buffer and advances the offset (1.0.2
  copied into its own argument); `MobiBuffer.fillInt64` no longer reads past
  the end of the data.

## 1.0.0

- Initial version.
