import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../config/config.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';

class CalibreTouch extends ConsumerStatefulWidget {
  const CalibreTouch({super.key});

  @override
  ConsumerState<CalibreTouch> createState() => _CalibreTouchState();
}

class _CalibreTouchState extends ConsumerState<CalibreTouch> {
  @override
  Widget build(BuildContext context) {
    final route = ref.watch(routesProvider);
    final mode = ref.watch(modeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode == 'dark' ? ThemeMode.dark : ThemeMode.light,
      routerConfig: route,
    );
  }

  @override
  void initState() {
    super.initState();
    initialization();
  }

  void initialization() async {
    await Future.delayed(const Duration(seconds: 1));
    FlutterNativeSplash.remove();
  }
}
