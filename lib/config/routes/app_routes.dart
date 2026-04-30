import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import '../../utils/utils.dart';
import '../config.dart';

final List<GoRoute> appRoutes = [
  GoRoute(
    path: RouteLocation.firstRun.name,
    parentNavigatorKey: navigationKey,
    builder: SplashPage.builder,
  ),
  GoRoute(
    path: RouteLocation.splash.name,
    parentNavigatorKey: navigationKey,
    builder: SplashPage.builder,
  ),
  GoRoute(
    path: RouteLocation.home.name,
    parentNavigatorKey: navigationKey,
    builder: HomePage.builder,
    routes: [
      GoRoute(
        path: RouteLocation.bookDetails.name,
        parentNavigatorKey: navigationKey,
        builder: BookDetails.builder,
      ),
      GoRoute(
        path: RouteLocation.updateBook.name,
        parentNavigatorKey: navigationKey,
        builder: UpdateBook.builder,
      ),
      GoRoute(
        path: RouteLocation.updateBook2.name,
        parentNavigatorKey: navigationKey,
        builder: UpdateBook2.builder,
      ),
    ],
  ),
];
