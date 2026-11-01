import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data_export.dart';
import 'path_provider.dart';
import 'shared_preferences_provider.dart';

/// Ids of the books last opened in one of the built-in readers, newest
/// first, at most [max], per library (SharedPreferences key
/// `recentBooks:<libraryPath>`). Used by the drawer's "Continue reading"
/// button (tap: newest, long press: the whole list).
class RecentBooksNotifier extends Notifier<List<int>> {
  static const int max = 10;

  String get _path => ref.read(pathProvider);
  String get _key => 'recentBooks:$_path';

  /// Single id kept by older versions; seeds the list once.
  String get _oldKey => 'lastReadBook:$_path';

  @override
  List<int> build() {
    // Another library has its own list.
    ref.watch(pathProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getStringList(_key);
    if (saved != null) {
      return saved.map(int.tryParse).nonNulls.toList();
    }
    final old = prefs.getInt(_oldKey);
    return old == null ? const [] : [old];
  }

  void add(Book book) {
    final id = book.id;
    if (id == null || state.firstOrNull == id) return;
    final ids = [id, ...state.where((e) => e != id)].take(max).toList();
    ref
        .read(sharedPreferencesProvider)
        .setStringList(_key, [for (final e in ids) '$e']);
    state = ids;
  }
}

final recentBooksProvider =
    NotifierProvider<RecentBooksNotifier, List<int>>(RecentBooksNotifier.new);

/// Id of the book last opened in a built-in reader, null = none yet.
final lastReadBookProvider =
    Provider<int?>((ref) => ref.watch(recentBooksProvider).firstOrNull);
