import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hu.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hu')
  ];

  /// App name
  ///
  /// In en, this message translates to:
  /// **'Calibre Touch'**
  String get appTitle;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'YES'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'NO'**
  String get no;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @noBookSelected.
  ///
  /// In en, this message translates to:
  /// **'No book selected'**
  String get noBookSelected;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchBook.
  ///
  /// In en, this message translates to:
  /// **'Search book'**
  String get searchBook;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @couldNotSaveBook.
  ///
  /// In en, this message translates to:
  /// **'Could not save book to database'**
  String get couldNotSaveBook;

  /// No description provided for @bookAdded.
  ///
  /// In en, this message translates to:
  /// **'Book added successfully'**
  String get bookAdded;

  /// No description provided for @duplicateTitle.
  ///
  /// In en, this message translates to:
  /// **'There is already a book with this title in the library!\nDo you still want to add it?'**
  String get duplicateTitle;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @changeView.
  ///
  /// In en, this message translates to:
  /// **'Change view'**
  String get changeView;

  /// No description provided for @viewCovers.
  ///
  /// In en, this message translates to:
  /// **'Covers'**
  String get viewCovers;

  /// No description provided for @viewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get viewList;

  /// No description provided for @viewTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get viewTable;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @publisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get publisher;

  /// No description provided for @series.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get series;

  /// No description provided for @seriesNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get seriesNumber;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @tagsCommaSeparated.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get tagsCommaSeparated;

  /// No description provided for @tagsHint.
  ///
  /// In en, this message translates to:
  /// **'Fantasy, Epic'**
  String get tagsHint;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @pages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get pages;

  /// No description provided for @pageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String pageCount(int count);

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @lastModified.
  ///
  /// In en, this message translates to:
  /// **'Last modified'**
  String get lastModified;

  /// No description provided for @path.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get path;

  /// No description provided for @filename.
  ///
  /// In en, this message translates to:
  /// **'Filename'**
  String get filename;

  /// No description provided for @id.
  ///
  /// In en, this message translates to:
  /// **'Id'**
  String get id;

  /// No description provided for @byAuthor.
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String byAuthor(String author);

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @editBook.
  ///
  /// In en, this message translates to:
  /// **'Edit book'**
  String get editBook;

  /// No description provided for @updateBook.
  ///
  /// In en, this message translates to:
  /// **'Update book'**
  String get updateBook;

  /// No description provided for @deleteBook.
  ///
  /// In en, this message translates to:
  /// **'Delete book'**
  String get deleteBook;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this book?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be removed from the library and its file will be deleted from disk.'**
  String deleteConfirmContent(String title);

  /// No description provided for @couldNotDeleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the book files: {error}'**
  String couldNotDeleteFiles(String error);

  /// No description provided for @bookDeleted.
  ///
  /// In en, this message translates to:
  /// **'Book deleted successfully'**
  String get bookDeleted;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(String error);

  /// No description provided for @titleEmpty.
  ///
  /// In en, this message translates to:
  /// **'Title cannot be empty'**
  String get titleEmpty;

  /// No description provided for @authorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Author cannot be empty'**
  String get authorEmpty;

  /// No description provided for @seriesNumberInvalid.
  ///
  /// In en, this message translates to:
  /// **'Series number must be a number, e.g. 1 or 2.5'**
  String get seriesNumberInvalid;

  /// No description provided for @invalidCharacters.
  ///
  /// In en, this message translates to:
  /// **'Title or author contains invalid characters'**
  String get invalidCharacters;

  /// No description provided for @bookUpdated.
  ///
  /// In en, this message translates to:
  /// **'Book updated successfully'**
  String get bookUpdated;

  /// No description provided for @savedFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Saved, but the book file was not found at: {path}'**
  String savedFileNotFound(String path);

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String updateFailed(String error);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Language of the app'**
  String get languageSubtitle;

  /// Always shown in the language itself
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Always shown in the language itself
  ///
  /// In en, this message translates to:
  /// **'Magyar'**
  String get languageHungarian;

  /// No description provided for @libraryQuestion.
  ///
  /// In en, this message translates to:
  /// **'Where should Calibre Touch keep your books?'**
  String get libraryQuestion;

  /// No description provided for @usingDefaultLocation.
  ///
  /// In en, this message translates to:
  /// **'Using the default location:'**
  String get usingDefaultLocation;

  /// No description provided for @usingCustomFolder.
  ///
  /// In en, this message translates to:
  /// **'Using a custom folder:'**
  String get usingCustomFolder;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @useDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get useDefault;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get darkTheme;

  /// No description provided for @darkThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch between light and dark appearance'**
  String get darkThemeSubtitle;

  /// No description provided for @storageNeeded.
  ///
  /// In en, this message translates to:
  /// **'Storage access is needed to use a custom folder.'**
  String get storageNeeded;

  /// No description provided for @storageRestricted.
  ///
  /// In en, this message translates to:
  /// **'Storage access is restricted on this device.'**
  String get storageRestricted;

  /// No description provided for @storageDenied.
  ///
  /// In en, this message translates to:
  /// **'Storage access was denied. Enable it in the app settings.'**
  String get storageDenied;

  /// No description provided for @folderPickerError.
  ///
  /// In en, this message translates to:
  /// **'Could not open folder picker: {error}'**
  String folderPickerError(String error);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Calibre Touch'**
  String get welcome;

  /// No description provided for @onboardingIntro.
  ///
  /// In en, this message translates to:
  /// **'Calibre library reader for touchscreen devices.'**
  String get onboardingIntro;

  /// No description provided for @onboardingStandalone.
  ///
  /// In en, this message translates to:
  /// **'Calibre touch can work as a standalone e-book library manager. This is not compatible Calibre.'**
  String get onboardingStandalone;

  /// No description provided for @allSet.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set!'**
  String get allSet;

  /// No description provided for @allSetDetails.
  ///
  /// In en, this message translates to:
  /// **'Your library and appearance are ready to go. You can always revisit these from the menu.'**
  String get allSetDetails;

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorMessage(String message);

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @readerContents.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get readerContents;

  /// No description provided for @readerSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading settings'**
  String get readerSettings;

  /// No description provided for @readerFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get readerFontSize;

  /// No description provided for @readerLineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get readerLineSpacing;

  /// No description provided for @readerTheme.
  ///
  /// In en, this message translates to:
  /// **'Page colour'**
  String get readerTheme;

  /// No description provided for @readerThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get readerThemeLight;

  /// No description provided for @readerThemeSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get readerThemeSepia;

  /// No description provided for @readerThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerThemeDark;

  /// No description provided for @readerThemeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get readerThemeAuto;

  /// No description provided for @readerDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get readerDarkMode;

  /// No description provided for @readerLightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get readerLightMode;

  /// No description provided for @readerPreviousChapter.
  ///
  /// In en, this message translates to:
  /// **'Previous chapter'**
  String get readerPreviousChapter;

  /// No description provided for @readerNextChapter.
  ///
  /// In en, this message translates to:
  /// **'Next chapter'**
  String get readerNextChapter;

  /// No description provided for @readerChapterOf.
  ///
  /// In en, this message translates to:
  /// **'Chapter {current} of {total}'**
  String readerChapterOf(int current, int total);

  /// No description provided for @readerOpenError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the book: {error}'**
  String readerOpenError(String error);

  /// No description provided for @readerUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The built-in reader can only open EPUB books (this one is {format}).'**
  String readerUnsupported(String format);

  /// No description provided for @readerZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get readerZoom;

  /// No description provided for @readerZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get readerZoomIn;

  /// No description provided for @readerZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get readerZoomOut;

  /// No description provided for @readerPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get readerPreviousPage;

  /// No description provided for @readerNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get readerNextPage;

  /// No description provided for @readerPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {count}'**
  String readerPageOf(int page, int count);

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @folderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Folder not found: {path}'**
  String folderNotFound(String path);

  /// No description provided for @folderOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the folder: {path}'**
  String folderOpenFailed(String path);

  /// No description provided for @builtInReader.
  ///
  /// In en, this message translates to:
  /// **'Built-in reader'**
  String get builtInReader;

  /// No description provided for @builtInReaderOn.
  ///
  /// In en, this message translates to:
  /// **'EPUB and PDF books open in Calibre Touch'**
  String get builtInReaderOn;

  /// No description provided for @builtInReaderOff.
  ///
  /// In en, this message translates to:
  /// **'EPUB and PDF books open in the system\'s default app'**
  String get builtInReaderOff;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no books in this library yet.'**
  String get libraryEmpty;

  /// No description provided for @libraryLocation.
  ///
  /// In en, this message translates to:
  /// **'Library folder: {path}'**
  String libraryLocation(String path);

  /// No description provided for @libraryNeedsStorage.
  ///
  /// In en, this message translates to:
  /// **'Calibre Touch has no access to this folder. Allow \"All files access\" to show your books.'**
  String get libraryNeedsStorage;

  /// No description provided for @libraryLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the library: {error}'**
  String libraryLoadError(String error);

  /// No description provided for @grantAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow access'**
  String get grantAccess;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @continueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get continueReading;

  /// No description provided for @noRecentBook.
  ///
  /// In en, this message translates to:
  /// **'No book opened yet'**
  String get noRecentBook;

  /// No description provided for @published.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get published;

  /// No description provided for @dateNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get dateNotSet;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get clearDate;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languages;

  /// No description provided for @languagesHint.
  ///
  /// In en, this message translates to:
  /// **'eng, hun'**
  String get languagesHint;

  /// No description provided for @identifiers.
  ///
  /// In en, this message translates to:
  /// **'Identifiers'**
  String get identifiers;

  /// No description provided for @identifiersHint.
  ///
  /// In en, this message translates to:
  /// **'isbn:9781234567897, goodreads:123'**
  String get identifiersHint;

  /// No description provided for @unknownLanguage.
  ///
  /// In en, this message translates to:
  /// **'Unknown language: {value}'**
  String unknownLanguage(String value);

  /// No description provided for @invalidIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Invalid identifier: {value}'**
  String invalidIdentifier(String value);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hu'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hu':
      return AppLocalizationsHu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
