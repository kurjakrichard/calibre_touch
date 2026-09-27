import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data_export.dart';
import 'path_provider.dart';

class SelectedBookNotifier extends Notifier<Book?> {
  @override
  Book? build() {
    // A book from the previous library must not stay selected.
    ref.watch(pathProvider);
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
