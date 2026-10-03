import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/utils.dart';
import 'shared_preferences_provider.dart';

/// The ways the home page can show the library.
///
/// - [grid]: the original Calibre Touch cover grid.
/// - [list]: cover + author + title cards, ported from Flutibre.
/// - [table]: sortable table of every field, ported from Flutibre Pro.
enum BookView {
  grid('Covers', Icons.grid_view),
  list('List', Icons.view_list),
  table('Table', Icons.table_chart_outlined);

  const BookView(this.label, this.icon);

  final String label;
  final IconData icon;

  static BookView fromName(String? name) => BookView.values.firstWhere(
        (v) => v.name == name,
        orElse: () => BookView.grid,
      );
}

/// Currently selected [BookView], remembered in SharedPreferences.
class BookViewNotifier extends Notifier<BookView> {
  @override
  BookView build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return BookView.fromName(prefs.getString(shareViewKey));
  }

  void setView(BookView view) {
    ref.read(sharedPreferencesProvider).setString(shareViewKey, view.name);
    state = view;
  }
}

final bookViewProvider = NotifierProvider<BookViewNotifier, BookView>(
  BookViewNotifier.new,
);
