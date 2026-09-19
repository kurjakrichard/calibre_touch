import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import '../../utils/utils.dart';
import '../config.dart';

final List<GoRoute> appRoutes = [
  GoRoute(
    name: Routes.firstRun.name,
    path: Routes.firstRun.path,
    parentNavigatorKey: navigationKey,
    builder: SplashPage.builder,
  ),
  GoRoute(
    name: Routes.splash.name,
    path: Routes.splash.path,
    parentNavigatorKey: navigationKey,
    builder: SplashPage.builder,
  ),
  GoRoute(
    name: Routes.home.name,
    path: Routes.home.path,
    parentNavigatorKey: navigationKey,
    builder: HomePage.builder,
    routes: [
      GoRoute(
        name: Routes.bookDetails.name,
        path: Routes.bookDetails.path,
        parentNavigatorKey: navigationKey,
        builder: BookDetails.builder,
      ),
      GoRoute(
        name: Routes.updateBook.name,
        path: Routes.updateBook.path,
        parentNavigatorKey: navigationKey,
        builder: UpdateBook.builder,
      ),
      GoRoute(
        name: Routes.updateBook2.name,
        path: Routes.updateBook2.path,
        parentNavigatorKey: navigationKey,
        builder: UpdateBook2.builder,
      ),
    ],
  ),
];
