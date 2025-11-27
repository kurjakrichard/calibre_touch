import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../config/config.dart';

class CalibreTouch extends ConsumerStatefulWidget {
  const CalibreTouch({super.key});

  @override
  ConsumerState<CalibreTouch> createState() => _CalibreTouchState();
}

class _CalibreTouchState extends ConsumerState<CalibreTouch> {
  @override
  Widget build(BuildContext context) {
    final route = ref.watch(routesProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: route,
    );
  }

  @override
  void initState() {
    super.initState();
    initialization();
  }

  void initialization() async {
    // This is where you can initialize the resources needed by your app while
    // the splash screen is displayed.  Remove the following example because
    // delaying the user experience is a bad design practice!
    // ignore_for_file: avoid_print

    await Future.delayed(const Duration(seconds: 1));
    FlutterNativeSplash.remove();
  }
}
