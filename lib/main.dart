import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'app/app.dart';
import 'providers/providers.dart';
import 'utils/utils.dart';

late SharedPreferences prefs;
void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      observers: [
        MyObserver(),
      ],
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CalibreTouch(),
    ),
  );
}
