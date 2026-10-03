import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Turns cover images found in book files into what Calibre keeps in a book
/// folder: a JPEG named cover.jpg. Pure Dart - call it from an isolate.
class CoverImage {
  CoverImage._();

  static const int _jpegQuality = 90;

  static bool isJpeg(Uint8List bytes) =>
      bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;

  /// JPEG bytes for any image the `image` package can decode (JPEG, PNG,
  /// GIF, WebP, BMP, ...). JPEGs are kept as they are. Transparent areas
  /// become white. Null if [bytes] is not a readable image (e.g. SVG).
  static Uint8List? toJpeg(Uint8List bytes) {
    if (isJpeg(bytes)) return bytes;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return encode(decoded);
  }

  /// Encodes [image] as JPEG, flattening transparency onto white.
  static Uint8List encode(img.Image image) {
    var source = image;
    if (source.hasAlpha) {
      final background = img.Image(width: source.width, height: source.height);
      img.fill(background, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(background, source);
      source = background;
    }
    return img.encodeJpg(source, quality: _jpegQuality);
  }

  /// JPEG from raw BGRA8888 pixels (what pdfrx renders).
  static Uint8List fromBgra(Uint8List pixels, int width, int height) {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      bytesOffset: pixels.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    // pdfrx renders onto an opaque white background, so alpha can be
    // ignored - the JPEG encoder only uses RGB.
    return img.encodeJpg(image, quality: _jpegQuality);
  }
}
