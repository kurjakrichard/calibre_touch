import 'package:flutter/foundation.dart' show immutable;

@immutable
class RouteLocation {
  const RouteLocation._();
  static String get home => '/homePage';
  static String get desktopDetails => '/desktopDetails';
  static String get updateBook => '/updateBook';
  static String get updateBook2 => '/updateBook2';
  static String get bookDetails => '/bookDetails';
}
