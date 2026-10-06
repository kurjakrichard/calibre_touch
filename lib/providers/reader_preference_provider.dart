import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/utils.dart';
import 'shared_preferences_provider.dart';

/// Whether books open in the built-in readers (true, default) - every
/// format in [BookDocuments] plus PDF - or in the platform's default app
/// (false). Saved in SharedPreferences
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

/// Whether the last book read (see [lastReadBookProvider]) opens
/// automatically when the app starts. Off by default. Saved in
/// SharedPreferences under `openLastBookOnStart`.
class OpenLastBookOnStartNotifier extends Notifier<bool> {
  static const _key = 'openLastBookOnStart';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_key) ?? false;
  }

  void set(bool value) {
    ref.read(sharedPreferencesProvider).setBool(_key, value);
    state = value;
  }
}

final openLastBookOnStartProvider =
    NotifierProvider<OpenLastBookOnStartNotifier, bool>(
  OpenLastBookOnStartNotifier.new,
);
