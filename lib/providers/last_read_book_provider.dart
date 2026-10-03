import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data_export.dart';
import 'path_provider.dart';
import 'shared_preferences_provider.dart';

/// Id of the book last opened in one of the built-in readers, per library
/// (SharedPreferences key `lastReadBook:<libraryPath>`). null = none yet.
/// Used by the drawer's "Continue reading" button.
class LastReadBookNotifier extends Notifier<int?> {
  String get _key => 'lastReadBook:${ref.read(pathProvider)}';

  @override
  int? build() {
    // Another library has its own last book.
    ref.watch(pathProvider);
    return ref.watch(sharedPreferencesProvider).getInt(_key);
  }

  void set(Book book) {
    final id = book.id;
    if (id == null || id == state) return;
    ref.read(sharedPreferencesProvider).setInt(_key, id);
    state = id;
  }
}

final lastReadBookProvider = NotifierProvider<LastReadBookNotifier, int?>(
  LastReadBookNotifier.new,
);
