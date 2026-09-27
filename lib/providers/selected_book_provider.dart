import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data_export.dart';

class SelectedBookNotifier extends Notifier<Book?> {
  @override
  Book? build() {
    return null;
  }

  Future<void> setSelectedBook(Book book) async {
    state = book;
  }

  Future<void> resetSelectedBook() async {
    state = null;
  }
}

final selectedBookProvider = NotifierProvider<SelectedBookNotifier, Book?>(
  SelectedBookNotifier.new,
);
