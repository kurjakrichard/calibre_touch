// Run with: flutter test test/relocate_book_test.dart
import 'dart:io';

import 'package:calibre_touch/utils/file_service.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('relocate_test');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> write(String relative, [String content = 'x']) async {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    await file.create(recursive: true);
    return file.writeAsString(content);
  }

  bool exists(String relative) =>
      File(p.joinAll([root.path, ...relative.split('/')])).existsSync();

  test('moves the folder with every format, the cover and other files',
      () async {
    await write('Old Author/Old Title/Old Author - Old Title.epub');
    await write('Old Author/Old Title/Old Author - Old Title.pdf');
    await write('Old Author/Old Title/cover.jpg');
    await write('Old Author/Old Title/metadata.opf');

    await FileService().relocateBook(
      fromPath: 'Old Author/Old Title',
      toPath: 'New Author/New Title (3)',
      fromName: 'Old Author - Old Title',
      toName: 'New Title - New Author',
      customPath: root.path,
    );

    expect(exists('New Author/New Title (3)/New Title - New Author.epub'), isTrue);
    expect(exists('New Author/New Title (3)/New Title - New Author.pdf'), isTrue);
    expect(exists('New Author/New Title (3)/cover.jpg'), isTrue);
    expect(exists('New Author/New Title (3)/metadata.opf'), isTrue);
    // Old, now empty folders are gone.
    expect(Directory(p.join(root.path, 'Old Author')).existsSync(), isFalse);
  });

  test('keeps the author folder when other books are still in it', () async {
    await write('Author/Book A (1)/Book A - Author.epub');
    await write('Author/Book B (2)/Book B - Author.epub');

    await FileService().relocateBook(
      fromPath: 'Author/Book A (1)',
      toPath: 'Author/Book C (1)',
      fromName: 'Book A - Author',
      toName: 'Book C - Author',
      customPath: root.path,
    );

    expect(exists('Author/Book C (1)/Book C - Author.epub'), isTrue);
    expect(exists('Author/Book B (2)/Book B - Author.epub'), isTrue);
  });

  test('never overwrites an existing folder', () async {
    await write('A/One (1)/One - A.epub');
    await write('A/Two (1)/Two - A.epub');
    expect(
      () => FileService().relocateBook(
        fromPath: 'A/One (1)',
        toPath: 'A/Two (1)',
        fromName: 'One - A',
        toName: 'Two - A',
        customPath: root.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('a missing book folder is reported', () async {
    expect(
      () => FileService().relocateBook(
        fromPath: 'Nobody/Nothing (9)',
        toPath: 'Nobody/Something (9)',
        fromName: 'Nothing - Nobody',
        toName: 'Something - Nobody',
        customPath: root.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
