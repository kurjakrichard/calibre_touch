import 'dart:io';
import 'package:calibre_touch/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import '../../utils/utils.dart';
import 'routes.dart';

final navigationKey = GlobalKey<NavigatorState>();
final routesProvider = Provider<GoRouter>(
  (ref) {
    // Decide the startup screen ONCE, here, instead of inside a route
    // builder. appRoutes already contains the real '/home' route (with its
    // own nested children) — do not wrap it in a second, duplicate '/home'
    // GoRoute, or every nested navigation ends up rebuilding this ancestor
    // route too (that's what caused the "/home/home/..." duplication and
    // the random bounce back to Home).
    final needsFirstRun =
        ref.read(sharedUtilityProvider).getPath().isNotEmpty;
    final isDesktop = Platform.isWindows || Platform.isLinux;
    final initialLocation = needsFirstRun
        ? Routes.firstRun.path
        : (isDesktop ? Routes.splash.path : Routes.home.path);

    return GoRouter(
      navigatorKey: navigationKey,
      initialLocation: initialLocation,
      errorBuilder: (context, state) => ErrorPage(error: state.error),
      routes: appRoutes,
    );
  },
);
