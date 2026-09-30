import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/utils.dart';
import 'shared_preferences_provider.dart';

/// Whether EPUB and PDF books open in the built-in readers (true, default)
/// or in the platform's default app (false). Saved in SharedPreferences
/// under [shareBuiltInReaderKey].
class UseBuiltInReaderNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(shareBuiltInReaderKey) ?? true;
  }

  void set(bool value) {
    ref.read(sharedPreferencesProvider).setBool(shareBuiltInReaderKey, value);
    state = value;
  }
}

final useBuiltInReaderProvider =
    NotifierProvider<UseBuiltInReaderNotifier, bool>(
  UseBuiltInReaderNotifier.new,
);
