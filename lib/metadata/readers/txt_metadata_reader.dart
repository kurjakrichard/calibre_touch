import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import '../book_metadata.dart';
import '../metadata_reader.dart';
import 'txt_text.dart';

/// Plain text: a .txt has no metadata, so title and author are guessed
/// from the file name and the first lines of the text (see
/// [guessTxtTitleAuthor]); the language from common words.
class TxtMetadataReader extends MetadataReader {
  const TxtMetadataReader();

  /// Only the start of the file is needed.
  static const int _sampleBytes = 64 * 1024;

  @override
  Set<String> get extensions => const {'txt'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() {
        final file = File(filePath).openSync();
        try {
          final bytes = file.readSync(_sampleBytes);
          return parseTxtMetadata(filePath, bytes);
        } finally {
          file.closeSync();
        }
      });
}

/// Title, author and language of a text file named [filePath] whose first
/// bytes are [bytes]. Pure Dart, safe in an isolate.
BookMetadata parseTxtMetadata(String filePath, Uint8List bytes) {
  final text = TxtText.decode(bytes);
  final language = TxtText.language(text);
  final guess = guessTxtTitleAuthor(filePath, text, language: language);
  return BookMetadata(
    title: guess.title,
    authors: guess.author.isEmpty ? const [] : [guess.author],
    languages: language == null ? const [] : [language],
  );
}

/// Title / author found by [guessTxtTitleAuthor] ('' = not found).
class TxtTitleAuthor {
  const TxtTitleAuthor(this.title, this.author);
  final String title;
  final String author;

  @override
  String toString() => '($title, $author)';
}

// "Title: ..." / "Author: ..." lines (Project Gutenberg and others).
final _titleLabel = RegExp(r'^(title|cím|cim|titel)\s*:\s*(.+)$',
    caseSensitive: false);
final _authorLabel = RegExp(
    r'^(author|authors|szerző|szerzo|írta|irta|autor|by)\s*:\s*(.+)$',
    caseSensitive: false);
// "by Jane Austen" / "Írta Jókai Mór" under the title.
final _byLine = RegExp(r'^(written by|by|írta|irta|von|par|di)\s+(.+)$',
    caseSensitive: false);
final _sentenceEnd = RegExp(r'''[.!?]["”']?$''');

/// Guesses title and author of a .txt, in this order:
/// 1. `Title:` / `Author:` lines near the start (Project Gutenberg);
/// 2. a `by X` / `Írta X` line, the title being the line above it;
/// 3. the file name `A - B` (Calibre's "Title - Author"; turned around
///    when only the first part looks like a person's name, e.g.
///    "Jókai Mór - Az arany ember");
/// 4. the short lines at the very top of the text: one that looks like a
///    name is the author, the other the title.
/// A file name that is just a number ("12345.txt", "pg1342") is not
/// used as a title.
TxtTitleAuthor guessTxtTitleAuthor(String filePath, String text,
    {String? language}) {
  var base = p.basenameWithoutExtension(filePath).replaceAll('_', ' ');
  base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
  final split = RegExp(r'^(.+?) - (.+)$').firstMatch(base);
  final fileA = split?.group(1)!.trim() ?? base;
  final fileB = split?.group(2)!.trim();

  final lines = _headLines(text);
  String? title;
  String? author;

  // 1) labels
  for (final line in lines) {
    final t = title == null ? _titleLabel.firstMatch(line) : null;
    if (t != null) {
      title = t.group(2)!.trim();
      continue;
    }
    final a = author == null ? _authorLabel.firstMatch(line) : null;
    if (a != null) author = a.group(2)!.trim();
  }

  // 2) "by X" with the title on the line above
  if (author == null) {
    for (var i = 0; i < lines.length && i < 12; i++) {
      final m = _byLine.firstMatch(lines[i]);
      if (m == null || !_isName(m.group(2)!)) continue;
      author = m.group(2)!.trim();
      if (title == null && i > 0 && lines[i - 1].length <= 80) {
        title = lines[i - 1];
      }
      break;
    }
  }

  // The short lines at the top, before the text proper starts.
  final front = <String>[];
  for (final line in lines.take(8)) {
    if (line.length > 80 ||
        (_sentenceEnd.hasMatch(line) && line.split(' ').length > 8)) {
      break;
    }
    front.add(line);
  }

  // 3) file name
  if (fileB != null) {
    final swap = _isName(fileA) && !_isName(fileB);
    title ??= swap ? fileB : fileA;
    author ??= swap ? fileA : fileB;
  } else if (!_isWeakFileName(fileA)) {
    title ??= fileA;
  }

  // 4) first lines of the text
  if (author == null) {
    final titleKey = _key(title ?? '');
    for (final line in front.take(4)) {
      if (_key(line) != titleKey && _isName(line)) {
        author = line;
        break;
      }
    }
  }
  if (title == null) {
    final candidates =
        front.take(4).where((l) => l != author && !_isName(l)).toList();
    title = candidates.isNotEmpty
        ? candidates.first
        : (front.isNotEmpty ? front.first : fileA);
  }

  if (author != null && _isUpper(author)) author = _titleCase(author);
  if (_isUpper(title) && title.length > 3) title = _recase(title, language);
  return TxtTitleAuthor(title, author ?? '');
}

/// First [count] non-empty lines (decorations like *** or === trimmed).
List<String> _headLines(String text, [int count = 40]) {
  final out = <String>[];
  var scanned = 0;
  for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
    if (++scanned > 400) break;
    final line = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[*_=#~\-\s]+|[*_=#~\-\s]+$'), '')
        .trim();
    if (line.isEmpty) continue;
    out.add(line);
    if (out.length >= count) break;
  }
  return out;
}

const _nameParticles = {
  'von', 'van', 'de', 'der', 'da', 'di', 'du', 'la', 'le', 'del', 'den', //
  'ter', 'y', 'e',
};
final _initial = RegExp(r'^\p{Lu}\.?$', unicode: true);
final _nameWord = RegExp(r"^\p{L}[\p{L}'’.\-]*$", unicode: true);

/// Looks like a person's name: 2-5 capitalised words ("Jókai Mór",
/// "J. R. R. Tolkien", "Ludwig van Beethoven"), no digits, not a
/// sentence.
bool _isName(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 50 || RegExp(r'\d').hasMatch(t)) return false;
  if (RegExp(r'[!?:;]$').hasMatch(t)) return false;
  if (t.endsWith('.') && !RegExp(r'\b\p{Lu}\.$', unicode: true).hasMatch(t)) {
    return false;
  }
  final words = t.replaceAll(',', ' ').split(' ').where((w) => w.isNotEmpty);
  if (words.length < 2 || words.length > 5) return false;
  for (final w in words) {
    if (_nameParticles.contains(w.toLowerCase())) continue;
    if (_initial.hasMatch(w)) continue;
    if (!_nameWord.hasMatch(w)) return false;
    final first = w.substring(0, 1);
    if (first != first.toUpperCase() || first == first.toLowerCase()) {
      return false;
    }
  }
  return true;
}

/// A file name that says nothing about the book: "12345", "pg1342",
/// mostly digits.
bool _isWeakFileName(String name) {
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(name).length;
  final digits = RegExp(r'\d').allMatches(name).length;
  return letters < 3 ||
      digits > letters ||
      RegExp(r'^(pg)?\d+([ \-].*)?$', caseSensitive: false).hasMatch(name);
}

/// Lower case letters and digits only, for comparing lines.
String _key(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

bool _isUpper(String s) {
  var letters = 0;
  for (final ch in s.split('')) {
    if (ch.toLowerCase() == ch.toUpperCase()) continue; // not a letter
    if (ch != ch.toUpperCase()) return false;
    letters++;
  }
  return letters >= 2;
}

String _capitalize(String w) =>
    w.isEmpty ? w : w.substring(0, 1).toUpperCase() + w.substring(1);

/// "JÓKAI MÓR" -> "Jókai Mór".
String _titleCase(String s) =>
    s.toLowerCase().split(' ').map(_capitalize).join(' ');

const _smallWords = {
  'a', 'an', 'the', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for', //
  'by', 'with', 'from',
};

/// An all-caps title in normal case: English "Pride and Prejudice",
/// other languages sentence case ("A kőszívű ember fiai").
String _recase(String title, String? language) {
  final words = title.toLowerCase().split(' ');
  if (language == 'eng') {
    return [
      for (var i = 0; i < words.length; i++)
        i > 0 && _smallWords.contains(words[i])
            ? words[i]
            : _capitalize(words[i]),
    ].join(' ');
  }
  return _capitalize(words.join(' '));
}
