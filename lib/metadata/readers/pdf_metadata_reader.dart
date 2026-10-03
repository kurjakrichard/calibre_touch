import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../book_metadata.dart';
import '../cover_image.dart';
import '../metadata_reader.dart';
import 'pdf_raw_metadata.dart';

/// PDF: title/author/... from the /Info dictionary and XMP
/// ([parsePdfMetadata], in an isolate), page count and a cover rendered
/// from the first page with pdfrx (as Calibre does for PDFs).
class PdfMetadataReader extends MetadataReader {
  const PdfMetadataReader();

  /// Height of the cover rendered from the first page, in pixels.
  static const double coverHeight = 1200;

  @override
  Set<String> get extensions => const {'pdf'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) async {
    var metadata = await Isolate.run(
        () => parsePdfMetadata(File(filePath).readAsBytesSync()));

    // Page count and cover need PDFium. A failure here (password-protected
    // file, ...) keeps the metadata read above.
    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(filePath);
      try {
        final pages = document.pages;
        metadata = metadata.copyWith(pageCount: pages.length);
        if (withCover && pages.isNotEmpty) {
          final cover = await _renderCover(pages.first);
          if (cover != null) metadata = metadata.copyWith(cover: cover);
        }
      } finally {
        await document.dispose();
      }
    } catch (e) {
      debugPrint('PDF pages/cover not read from $filePath: $e');
    }
    return metadata;
  }

  static Future<Uint8List?> _renderCover(PdfPage page) async {
    if (page.width <= 0 || page.height <= 0) return null;
    final scale = coverHeight / page.height;
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: coverHeight,
      backgroundColor: 0xffffffff,
    );
    if (image == null) return null;
    final int width;
    final int height;
    final Uint8List pixels;
    try {
      width = image.width;
      height = image.height;
      // Copy: the rendered buffer is freed by dispose().
      pixels = Uint8List.fromList(image.pixels);
    } finally {
      image.dispose();
    }
    return Isolate.run(() => CoverImage.fromBgra(pixels, width, height));
  }
}
