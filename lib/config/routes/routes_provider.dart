import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import 'routes.dart';

final navigationKey = GlobalKey<NavigatorState>();
final routesProvider = Provider<GoRouter>(
  (ref) {
    return GoRouter(navigatorKey: navigationKey, routes: <RouteBase>[
      GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) {
            return const HomePage();
          },
          routes: appRoutes),
    ]);
  },
);
