import 'package:calibre_touch/utils/utils.dart';
import 'package:flutter/material.dart';

// Both themes set the same settings in the same order, so they can be
// compared line by line. Keep it that way when adding a setting.

/// Light theme: [buttonColor] bars and buttons on [scaffoldColor] /
/// [panelColor] backgrounds.
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  // Accents not set below (date picker, progress indicator, dropdown, ...)
  // use buttonColor instead of the default Material 3 purple.
  colorScheme: ColorScheme.fromSeed(
    seedColor: buttonColor,
    brightness: Brightness.light,
    primary: buttonColor,
    onPrimary: onButtonColor,
  ),
  fontFamily: appFontFamily,
  scaffoldBackgroundColor: scaffoldColor,

  // Text
  textTheme: Typography.blackMountainView
      .apply(bodyColor: mainFontColor, displayColor: mainFontColor),
  primaryTextTheme: Typography.whiteMountainView
      .apply(bodyColor: onButtonColor, displayColor: onButtonColor),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: buttonColor,
    selectionColor: lightTextSelectionColor,
    selectionHandleColor: buttonColor,
  ),

  // Icons (also the rating stars) and list tiles
  iconTheme: const IconThemeData(color: mainFontColor),
  listTileTheme: const ListTileThemeData(
      textColor: mainFontColor, iconColor: mainFontColor),

  // Bars
  appBarTheme: const AppBarTheme(
    backgroundColor: buttonColor,
    foregroundColor: onButtonColor,
  ),

  // Buttons
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: buttonColor,
      foregroundColor: onButtonColor,
      iconColor: onButtonColor,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? disabledButtonColor
              : buttonColor),
      side: WidgetStateProperty.resolveWith((states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? disabledButtonColor
              : buttonColor)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: buttonColor),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: buttonColor,
    foregroundColor: onButtonColor,
  ),

  // Controls
  // Chips (e.g. the format chips on the details page) look like buttons.
  chipTheme: const ChipThemeData(
    backgroundColor: buttonColor,
    labelStyle: TextStyle(color: onButtonColor),
    iconTheme: IconThemeData(color: onButtonColor),
    side: BorderSide.none,
  ),
  // Switches (e.g. SwitchListTile): buttonColor when on, panelColor when off.
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? onButtonColor : null),
    trackColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? buttonColor : panelColor),
  ),

  // Surfaces
  drawerTheme: const DrawerThemeData(backgroundColor: panelColor),
  dialogTheme: const DialogThemeData(
    backgroundColor: dialogBackgroundColor,
    titleTextStyle: TextStyle(
        color: buttonColor, fontSize: 24, fontFamily: appFontFamily),
    contentTextStyle: TextStyle(color: dialogTextColor),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: buttonColor,
    contentTextStyle: TextStyle(color: onButtonColor),
  ),
);

/// Dark theme: white text, icons and accents on dark backgrounds instead of
/// the default Material 3 purple.
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  // Accents not set below (date picker, progress indicator, dropdown, ...)
  // are white instead of the default Material 3 purple.
  colorScheme: ColorScheme.fromSeed(
    seedColor: buttonColor,
    brightness: Brightness.dark,
    primary: darkFontColor,
    onPrimary: darkListBackground,
  ),
  fontFamily: appFontFamily,
  scaffoldBackgroundColor: darkScaffoldColor,

  // Text
  textTheme: Typography.whiteMountainView
      .apply(bodyColor: darkFontColor, displayColor: darkFontColor),
  primaryTextTheme: Typography.whiteMountainView
      .apply(bodyColor: darkFontColor, displayColor: darkFontColor),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: darkFontColor,
    selectionColor: darkTextSelectionColor,
    selectionHandleColor: darkFontColor,
  ),

  // Icons (also the rating stars) and list tiles
  iconTheme: const IconThemeData(color: darkFontColor),
  listTileTheme: const ListTileThemeData(
      textColor: darkFontColor, iconColor: darkFontColor),

  // Bars
  appBarTheme: const AppBarTheme(
    backgroundColor: darkScaffoldColor,
    foregroundColor: darkFontColor,
  ),

  // Buttons
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: darkButtonColor,
      foregroundColor: darkFontColor,
      iconColor: darkFontColor,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? darkDisabledColor
              : darkFontColor),
      side: WidgetStateProperty.resolveWith((states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? darkDisabledColor
              : darkFontColor)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: darkFontColor),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: darkButtonColor,
    foregroundColor: darkFontColor,
  ),

  // Controls
  // Chips (e.g. the format chips on the details page) look like buttons.
  chipTheme: const ChipThemeData(
    backgroundColor: darkButtonColor,
    labelStyle: TextStyle(color: darkFontColor),
    iconTheme: IconThemeData(color: darkFontColor),
    side: BorderSide.none,
  ),
  // Switches (e.g. SwitchListTile): white track when on, default when off.
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? darkSwitchThumbColor : null),
    trackColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? darkFontColor : null),
  ),

  // Surfaces
  drawerTheme:
      const DrawerThemeData(backgroundColor: darkDrawerBackgroundColor),
  dialogTheme: const DialogThemeData(
    backgroundColor: darkDialogBackgroundColor,
    titleTextStyle: TextStyle(
        color: darkFontColor, fontSize: 24, fontFamily: appFontFamily),
    contentTextStyle: TextStyle(color: darkFontColor),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: buttonColor,
    contentTextStyle: TextStyle(color: onButtonColor),
  ),
);
