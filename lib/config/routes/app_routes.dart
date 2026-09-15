import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import '../../utils/utils.dart';
import '../config.dart';

final List<GoRoute> appRoutes = [
  GoRoute(
    name: Routes.firstRun.name,
    path: Routes.firstRun.name,
    parentNavigatorKey: navigationKey,
    builder: SplashPage.builder,
  ),
  GoRoute(
    name: Routes.splash.name,
    path: Routes.splash.name,
    parentNavigatorKey: navigationKey,
    builder: SplashPage.builder,
  ),
  GoRoute(
    name: Routes.home.name,
    path: Routes.home.name,
    parentNavigatorKey: navigationKey,
    builder: HomePage.builder,
    routes: [
      GoRoute(
        name: Routes.desktopDetails.name,
        path: Routes.bookDetails.name,
        parentNavigatorKey: navigationKey,
        builder: BookDetails.builder,
      ),
      GoRoute(
        name: Routes.updateBook.name,
        path: Routes.updateBook.name,
        parentNavigatorKey: navigationKey,
        builder: UpdateBook.builder,
      ),
      GoRoute(
        name: Routes.updateBook2.name,
        path: Routes.updateBook2.name,
        parentNavigatorKey: navigationKey,
        builder: UpdateBook2.builder,
      ),
    ],
  ),
];
