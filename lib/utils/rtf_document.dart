import 'dart:typed_data';
import '../metadata/readers/rtf_parser.dart';
import 'utils.dart';

/// Opens Rich Text Format (.rtf) books for the built-in reader, using
/// [RtfParser]: paragraphs with bold/italic/underline, headings (outline
/// levels or "Heading N" styles), centred lines and PNG/JPEG pictures.
///
/// Pure Dart: call [RtfDocument.parse] through `compute`.
class RtfDocument {
  RtfDocument._();

  static const extensions = {'rtf'};

  static Future<EpubDocument> parse(Uint8List bytes) async {
    if (!RtfParser.isRtf(bytes)) {
      throw const FormatException('Not an RTF file');
    }
    final content = RtfParser.parse(bytes);
    final blocks = <DocBlock>[];
    var blanks = 0;
    for (final para in content.paragraphs) {
      if (para.text.isEmpty && !para.html.contains('<img')) {
        blanks++;
        continue;
      }
      final align = para.center ? ' style="text-align:center"' : '';
      if (para.title) {
        blocks.add(DocBlock('<h1$align>${para.html}</h1>',
            text: para.text, blanksBefore: blanks));
      } else if (para.heading > 0) {
        final tag = 'h${(para.heading + 1).clamp(2, 6)}';
        blocks.add(DocBlock('<$tag>${para.html}</$tag>',
            text: para.text, heading: para.heading, blanksBefore: blanks));
      } else {
        blocks.add(DocBlock('<p$align>${para.html}</p>',
            text: para.text, paragraph: true, blanksBefore: blanks));
      }
      blanks = 0;
    }
    return DocumentBuilder.build(blocks, files: content.images);
  }
}
