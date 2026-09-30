import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/utils.dart';
import 'shared_preferences_provider.dart';

/// Languages the app is translated to (see lib/l10n/*.arb).
const List<String> appLanguages = ['en', 'hu'];

/// The app's language, saved in SharedPreferences under [shareLocaleKey].
/// Until the user picks one, the device language is used if it's supported
/// (otherwise English).
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getString(shareLocaleKey);
    if (saved != null && appLanguages.contains(saved)) return Locale(saved);
    final device = PlatformDispatcher.instance.locale.languageCode;
    return Locale(appLanguages.contains(device) ? device : 'en');
  }

  void setLanguage(String languageCode) {
    if (!appLanguages.contains(languageCode)) return;
    ref.read(sharedUtilityProvider).setLocale(locale: languageCode);
    state = Locale(languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
