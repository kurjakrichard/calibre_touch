import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import '../config.dart';

final List<GoRoute> appRoutes = [
  GoRoute(
    path: RouteLocation.home,
    parentNavigatorKey: navigationKey,
    builder: HomePage.builder,
  ),
  GoRoute(
    path: RouteLocation.bookDetails,
    parentNavigatorKey: navigationKey,
    builder: BookDetails.builder,
  ),
  GoRoute(
    path: RouteLocation.updateBook,
    parentNavigatorKey: navigationKey,
    builder: UpdateBook.builder,
  ),
];
