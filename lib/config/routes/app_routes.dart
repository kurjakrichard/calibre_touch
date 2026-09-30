import 'package:go_router/go_router.dart';
import '../../pages/pages.dart';
import '../../utils/utils.dart';
import '../config.dart';

final List<GoRoute> appRoutes = [
  GoRoute(
    name: Routes.firstRun.name,
    path: Routes.firstRun.path,
    parentNavigatorKey: navigationKey,
    builder: OnboardingPage.builder,
  ),
  GoRoute(
    name: Routes.settings.name,
    path: Routes.settings.path,
    parentNavigatorKey: navigationKey,
    builder: SettingsPage.builder,
  ),
  GoRoute(
    // Full-screen e-book reader (outside /home, so nothing of the library
    // screen stays around it).
    name: Routes.reader.name,
    path: Routes.reader.path,
    parentNavigatorKey: navigationKey,
    pageBuilder: ReaderPage.pageBuilder,
  ),
  GoRoute(
    // Full-screen PDF reader.
    name: Routes.pdfReader.name,
    path: Routes.pdfReader.path,
    parentNavigatorKey: navigationKey,
    pageBuilder: PdfReaderPage.pageBuilder,
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
    ],
  ),
];
