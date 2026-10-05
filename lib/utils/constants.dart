import 'package:flutter/material.dart';

const String sharedDarkModeKey = 'darkTheme';
const String shareLocaleKey = 'locale';
const String shareModeKey = 'mode';
const String sharePathKey = 'path';
const String sharedIsFirstRunKey = 'isFirstRun';
const String shareViewKey = 'bookView';
const String shareBuiltInReaderKey = 'useBuiltInReader';
const double maxWidth = 900;

/// Font family of both themes (also the dialog titles).
const String appFontFamily = 'Roboto';
const String dbTable = 'books';
const String dbName = 'metadata.db';

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

// App palette
const Color scaffoldColor = Color.fromRGBO(242, 249, 254, 1);
const Color panelColor = Color.fromRGBO(219, 228, 243, 1);
const Color buttonColor = Color.fromRGBO(62, 71, 132, 1);

/// Text and icons in light mode.
const Color mainFontColor = Colors.black;

/// Text/icons drawn on top of [buttonColor] (app bar, buttons, snackbar).
const Color onButtonColor = Colors.white;

/// Selected text background in light mode ([buttonColor] at 40%).
const Color lightTextSelectionColor = Color.fromRGBO(62, 71, 132, 0.4);
const Color dialogBackgroundColor = Colors.white;
const Color dialogTextColor = Colors.black;

/// [buttonColor] at 50%.
const Color disabledButtonColor = Color.fromRGBO(62, 71, 132, 0.5);
const Color errorTextColor = Colors.red;
const Color transparentColor = Colors.transparent;

/// Search field in the app bar (on [buttonColor]).
const Color searchHintColor = Colors.white70;

/// Book cover shadow on the details panel.
const Color coverShadowColor = Color(0xFFF57F17);

/// Default colour of the rating stars.
const Color ratingStarColor = mainFontColor;

/// Opacity of the empty rating stars.
const double emptyStarOpacity = 0.6;

/// Splash screen and onboarding header background.
const Color splashBackgroundColor = Color.fromRGBO(28, 47, 67, 1);
const Color splashTextColor = Colors.white;

// Book list / table (light theme) - translucent tints of [buttonColor]
const Color selectedBookColor = Color.fromRGBO(62, 71, 132, 0.30);
const Color bookHighlightColor = Color.fromRGBO(62, 71, 132, 0.12);
const Color bookSplashColor = Color.fromRGBO(62, 71, 132, 0.20);
const Color listStripeColor = Color.fromRGBO(29, 27, 32, 0.04);

// Dark theme
/// Text, icons and accents in dark mode.
const Color darkFontColor = Colors.white;

/// Selected text background in dark mode (e.g. the book description).
const Color darkTextSelectionColor = Color.fromRGBO(255, 255, 255, 0.3);

/// Disabled buttons in dark mode.
const Color darkDisabledColor = Color.fromRGBO(255, 255, 255, 0.38);

/// Page and app bar background in dark mode.
const Color darkScaffoldColor = Color(0xFF141218);

/// Dialog background in dark mode.
const Color darkDialogBackgroundColor = Color(0xFF2B2930);

// Dark drawer
/// Drawer background in dark mode (the Material 3 default dark surface).
const Color darkDrawerBackgroundColor = Color(0xFF1D1B20);
const Color darkDrawerTextColor = darkFontColor;
const Color darkDrawerDisabledColor = Color.fromRGBO(255, 255, 255, 0.5);

/// Elevated buttons, floating action button and chips in dark mode
/// (same as the drawer background).
const Color darkButtonColor = darkDrawerBackgroundColor;

// Dark book list / table
const Color darkListBackground = Color.fromRGBO(38, 42, 56, 1);

/// [buttonColor] at 85%.
const Color darkSelectedBookColor = Color.fromRGBO(62, 71, 132, 0.85);
const Color darkBookHighlightColor = Color.fromRGBO(84, 96, 170, 1);
const Color darkBookSplashColor = Color.fromARGB(60, 255, 255, 255);
const Color darkListStripeColor = Color.fromRGBO(230, 224, 233, 0.04);

/// Switch thumb when the switch is on (on a [darkFontColor] track).
const Color darkSwitchThumbColor = darkListBackground;

// Reader themes (background, text, bar)
const Color readerLightBackground = Color(0xFFFFFFFF);
const Color readerLightText = Color(0xFF1F1F1F);
const Color readerLightBar = Color(0xFFF1F1F1);
const Color readerSepiaBackground = Color(0xFFF4ECD8);
const Color readerSepiaText = Color(0xFF5B4636);
const Color readerSepiaBar = Color(0xFFE8DDC4);
const Color readerDarkBackground = Color(0xFF121212);
const Color readerDarkText = Color(0xFFD6D6D6);
const Color readerDarkBar = Color(0xFF1E1E1E);

/// Opacity of secondary text in the reader (on top of the theme text colour).
const double readerSecondaryTextOpacity = 0.7;

/// PDF viewer background around the pages (before the colour filter).
const Color pdfViewerBackground = Color(0xFFDDDDDD);
