import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'book_export.dart';

final booksProvider = NotifierProvider<BookNotifier, BookState>(
  BookNotifier.new,
);
