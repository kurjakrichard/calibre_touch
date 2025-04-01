import 'package:calibre_touch/utils/utils.dart';
import 'package:flutter/material.dart';

ThemeData darkTheme =
    ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto');

ThemeData lightTheme = ThemeData(
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: buttoncolor,
      unselectedItemColor: Colors.grey,
      selectedItemColor: Colors.white),
  appBarTheme: const AppBarTheme(
    backgroundColor: buttoncolor,
    foregroundColor: Colors.white,
  ),
  scaffoldBackgroundColor: primary,
  fontFamily: 'Roboto',
  dialogTheme: const DialogTheme(
    backgroundColor: Colors.white,
    contentTextStyle: TextStyle(color: Colors.black),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: buttoncolor, foregroundColor: Colors.white),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: buttoncolor,
    ),
  ),
);
