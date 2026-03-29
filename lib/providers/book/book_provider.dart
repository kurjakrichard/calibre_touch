import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../data/data_export.dart';
import 'book_export.dart';

final booksProvider = StateNotifierProvider<BookNotifier, BookState>((ref) {
  final repository = ref.watch(bookRepositoryProvider);
  return BookNotifier(repository);
});
