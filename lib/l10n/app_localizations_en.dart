// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Calibre Touch';

  @override
  String get yes => 'YES';

  @override
  String get no => 'NO';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get settings => 'Settings';

  @override
  String get noBookSelected => 'No book selected';

  @override
  String get search => 'Search';

  @override
  String get searchBook => 'Search book';

  @override
  String get closeSearch => 'Close search';

  @override
  String get couldNotSaveBook => 'Could not save book to database';

  @override
  String get bookAdded => 'Book added successfully';

  @override
  String get duplicateTitle =>
      'There is already a book with this title in the library!\nDo you still want to add it?';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String unsupportedFormat(String file) {
    return 'This file type isn\'t an e-book format: $file';
  }

  @override
  String get changeView => 'Change view';

  @override
  String get viewCovers => 'Covers';

  @override
  String get viewList => 'List';

  @override
  String get viewTable => 'Table';

  @override
  String get title => 'Title';

  @override
  String get author => 'Author';

  @override
  String get publisher => 'Publisher';

  @override
  String get series => 'Series';

  @override
  String get seriesNumber => 'Number';

  @override
  String get tags => 'Tags';

  @override
  String get tagsCommaSeparated => 'Tags (comma separated)';

  @override
  String get tagsHint => 'Fantasy, Epic';

  @override
  String get description => 'Description';

  @override
  String get date => 'Date';

  @override
  String get format => 'Format';

  @override
  String get formats => 'Formats';

  @override
  String get chooseFormat => 'Choose a format';

  @override
  String get rating => 'Rating';

  @override
  String get pages => 'Pages';

  @override
  String pageCount(int count) {
    return '$count pages';
  }

  @override
  String get price => 'Price';

  @override
  String get lastModified => 'Last modified';

  @override
  String get path => 'Path';

  @override
  String get filename => 'Filename';

  @override
  String get id => 'Id';

  @override
  String byAuthor(String author) {
    return 'by $author';
  }

  @override
  String get open => 'Open';

  @override
  String get edit => 'Edit';

  @override
  String get details => 'Details';

  @override
  String get editBook => 'Edit book';

  @override
  String get updateBook => 'Update book';

  @override
  String get deleteBook => 'Delete book';

  @override
  String get deleteConfirmTitle => 'Are you sure you want to delete this book?';

  @override
  String deleteConfirmContent(String title) {
    return '\"$title\" will be removed from the library and its file will be deleted from disk.';
  }

  @override
  String couldNotDeleteFiles(String error) {
    return 'Could not delete the book files: $error';
  }

  @override
  String get bookDeleted => 'Book deleted successfully';

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get titleEmpty => 'Title cannot be empty';

  @override
  String get authorEmpty => 'Author cannot be empty';

  @override
  String get seriesNumberInvalid =>
      'Series number must be a number, e.g. 1 or 2.5';

  @override
  String get invalidCharacters => 'Title or author contains invalid characters';

  @override
  String get bookUpdated => 'Book updated successfully';

  @override
  String savedFileNotFound(String path) {
    return 'Saved, but the book file was not found at: $path';
  }

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'Language of the app';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHungarian => 'Magyar';

  @override
  String get libraryQuestion => 'Where should Calibre Touch keep your books?';

  @override
  String get usingDefaultLocation => 'Using the default location:';

  @override
  String get usingCustomFolder => 'Using a custom folder:';

  @override
  String get loading => 'Loading…';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get useDefault => 'Use default';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get darkThemeSubtitle => 'Switch between light and dark appearance';

  @override
  String get storageNeeded =>
      'Storage access is needed to use a custom folder.';

  @override
  String get storageRestricted =>
      'Storage access is restricted on this device.';

  @override
  String get storageDenied =>
      'Storage access was denied. Enable it in the app settings.';

  @override
  String folderPickerError(String error) {
    return 'Could not open folder picker: $error';
  }

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get getStarted => 'Get Started';

  @override
  String get welcome => 'Welcome to Calibre Touch';

  @override
  String get onboardingIntro =>
      'Calibre library reader for touchscreen devices.';

  @override
  String get onboardingStandalone =>
      'Calibre touch can work as a standalone e-book library manager. This is not compatible Calibre.';

  @override
  String get allSet => 'You\'re all set!';

  @override
  String get allSetDetails =>
      'Your library and appearance are ready to go. You can always revisit these from the menu.';

  @override
  String errorMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get read => 'Read';

  @override
  String get readerContents => 'Contents';

  @override
  String get readerSettings => 'Reading settings';

  @override
  String get readerFontSize => 'Font size';

  @override
  String get readerLineSpacing => 'Line spacing';

  @override
  String get readerJustify => 'Justified text';

  @override
  String get readerTheme => 'Page colour';

  @override
  String get readerThemeLight => 'Light';

  @override
  String get readerThemeSepia => 'Sepia';

  @override
  String get readerThemeDark => 'Dark';

  @override
  String get readerThemeAuto => 'Auto';

  @override
  String get readerDarkMode => 'Dark mode';

  @override
  String get readerLightMode => 'Light mode';

  @override
  String get readerPreviousChapter => 'Previous chapter';

  @override
  String get readerNextChapter => 'Next chapter';

  @override
  String readerChapterOf(int current, int total) {
    return 'Chapter $current of $total';
  }

  @override
  String readerOpenError(String error) {
    return 'Could not open the book: $error';
  }

  @override
  String get readerDrmProtected =>
      'This book is DRM-protected, so it can\'t be opened.';

  @override
  String readerUnsupported(String format) {
    return 'The built-in reader can\'t open $format books.';
  }

  @override
  String get readerZoom => 'Zoom';

  @override
  String get readerZoomIn => 'Zoom in';

  @override
  String get readerZoomOut => 'Zoom out';

  @override
  String get readerPreviousPage => 'Previous page';

  @override
  String get readerNextPage => 'Next page';

  @override
  String readerPageOf(int page, int count) {
    return 'Page $page of $count';
  }

  @override
  String get openFolder => 'Open folder';

  @override
  String folderNotFound(String path) {
    return 'Folder not found: $path';
  }

  @override
  String folderOpenFailed(String path) {
    return 'Could not open the folder: $path';
  }

  @override
  String get builtInReader => 'Built-in reader';

  @override
  String builtInReaderOn(String formats) {
    return 'Opens in Calibre Touch: $formats';
  }

  @override
  String get builtInReaderOff => 'Books open in the system\'s default app';

  @override
  String get openLastBook => 'Open last book on startup';

  @override
  String get openLastBookSubtitle =>
      'Continue reading the last book when the app starts';

  @override
  String get libraryEmpty => 'There are no books in this library yet.';

  @override
  String libraryLocation(String path) {
    return 'Library folder: $path';
  }

  @override
  String get libraryNeedsStorage =>
      'Calibre Touch has no access to this folder. Allow \"All files access\" to show your books.';

  @override
  String libraryLoadError(String error) {
    return 'Could not open the library: $error';
  }

  @override
  String get grantAccess => 'Allow access';

  @override
  String get retry => 'Retry';

  @override
  String get continueReading => 'Continue reading';

  @override
  String get noRecentBook => 'No book opened yet';

  @override
  String get published => 'Published';

  @override
  String get dateNotSet => 'Not set';

  @override
  String get clearDate => 'Clear date';

  @override
  String get languages => 'Languages';

  @override
  String get languagesHint => 'eng, hun';

  @override
  String get identifiers => 'Identifiers';

  @override
  String get identifiersHint => 'isbn:9781234567897, goodreads:123';

  @override
  String unknownLanguage(String value) {
    return 'Unknown language: $value';
  }

  @override
  String invalidIdentifier(String value) {
    return 'Invalid identifier: $value';
  }

  @override
  String get alreadyInLibrary => 'Already in your library';

  @override
  String alreadyInLibraryText(String title, String author, String formats) {
    return '\"$title\" by $author is already in the library ($formats).';
  }

  @override
  String get openLibraryCopy => 'Open the library copy';

  @override
  String get showLibraryCopy => 'Show the library copy';

  @override
  String addAsFormat(String format) {
    return 'Add $format to this book';
  }

  @override
  String get addAsNewBook => 'Add as a new book';

  @override
  String get cancel => 'Cancel';

  @override
  String formatAdded(String format) {
    return '$format added to the book';
  }

  @override
  String booksAdded(int count) {
    return '$count books added';
  }

  @override
  String get libraryDamaged => 'The library database (metadata.db) is damaged.';

  @override
  String get databaseDamagedTitle => 'The library database is damaged';

  @override
  String get databaseDamagedText =>
      'metadata.db exists but could not be opened. Would you like to rebuild the database from the metadata.opf files in the book folders? The damaged file is kept as a backup.';

  @override
  String get rebuildDatabase => 'Rebuild database';

  @override
  String get rebuildingDatabase =>
      'Rebuilding the database from metadata.opf files…';

  @override
  String rebuildDone(int count) {
    return '$count books restored.';
  }

  @override
  String rebuildRenumbered(int count) {
    return '$count books got a new id (missing or duplicate id).';
  }

  @override
  String rebuildSkipped(int count) {
    return '$count book folders could not be read:';
  }

  @override
  String rebuildBackup(String file) {
    return 'The old database was saved as $file.';
  }

  @override
  String rebuildFailed(String error) {
    return 'Rebuilding the database failed: $error';
  }
}
