// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hungarian (`hu`).
class AppLocalizationsHu extends AppLocalizations {
  AppLocalizationsHu([String locale = 'hu']) : super(locale);

  @override
  String get appTitle => 'Calibre Touch';

  @override
  String get yes => 'IGEN';

  @override
  String get no => 'NEM';

  @override
  String get save => 'Mentés';

  @override
  String get delete => 'Törlés';

  @override
  String get done => 'Kész';

  @override
  String get settings => 'Beállítások';

  @override
  String get noBookSelected => 'Nincs könyv kiválasztva';

  @override
  String get search => 'Keresés';

  @override
  String get searchBook => 'Könyv keresése';

  @override
  String get closeSearch => 'Keresés bezárása';

  @override
  String get couldNotSaveBook =>
      'Nem sikerült a könyvet az adatbázisba menteni';

  @override
  String get bookAdded => 'Könyv sikeresen hozzáadva';

  @override
  String get duplicateTitle =>
      'Már van ilyen című könyv a könyvtárban!\nBiztos hozzáadod?';

  @override
  String importFailed(String error) {
    return 'Az importálás sikertelen: $error';
  }

  @override
  String get changeView => 'Nézet váltása';

  @override
  String get viewCovers => 'Borítók';

  @override
  String get viewList => 'Lista';

  @override
  String get viewTable => 'Táblázat';

  @override
  String get title => 'Cím';

  @override
  String get author => 'Szerző';

  @override
  String get publisher => 'Kiadó';

  @override
  String get series => 'Sorozat';

  @override
  String get seriesNumber => 'Szám';

  @override
  String get tags => 'Címkék';

  @override
  String get tagsCommaSeparated => 'Címkék (vesszővel elválasztva)';

  @override
  String get tagsHint => 'Fantasy, Kaland';

  @override
  String get description => 'Leírás';

  @override
  String get date => 'Dátum';

  @override
  String get format => 'Formátum';

  @override
  String get rating => 'Értékelés';

  @override
  String get pages => 'Oldalak';

  @override
  String pageCount(int count) {
    return '$count oldal';
  }

  @override
  String get price => 'Ár';

  @override
  String get lastModified => 'Utoljára módosítva';

  @override
  String get path => 'Útvonal';

  @override
  String get filename => 'Fájlnév';

  @override
  String get id => 'Azonosító';

  @override
  String byAuthor(String author) {
    return 'Szerző: $author';
  }

  @override
  String get open => 'Megnyitás';

  @override
  String get edit => 'Szerkesztés';

  @override
  String get details => 'Részletek';

  @override
  String get editBook => 'Könyv szerkesztése';

  @override
  String get updateBook => 'Könyv szerkesztése';

  @override
  String get deleteBook => 'Könyv törlése';

  @override
  String get deleteConfirmTitle => 'Biztosan törlöd ezt a könyvet?';

  @override
  String deleteConfirmContent(String title) {
    return 'A(z) \"$title\" kikerül a könyvtárból, és a fájlja törlődik a lemezről.';
  }

  @override
  String couldNotDeleteFiles(String error) {
    return 'Nem sikerült törölni a könyv fájljait: $error';
  }

  @override
  String get bookDeleted => 'Könyv sikeresen törölve';

  @override
  String deleteFailed(String error) {
    return 'A törlés sikertelen: $error';
  }

  @override
  String get titleEmpty => 'A cím nem lehet üres';

  @override
  String get authorEmpty => 'A szerző nem lehet üres';

  @override
  String get seriesNumberInvalid => 'A sorozatszám szám legyen, pl. 1 vagy 2.5';

  @override
  String get invalidCharacters =>
      'A cím vagy a szerző érvénytelen karaktert tartalmaz';

  @override
  String get bookUpdated => 'Könyv sikeresen frissítve';

  @override
  String savedFileNotFound(String path) {
    return 'Mentve, de a könyv fájlja nem található itt: $path';
  }

  @override
  String updateFailed(String error) {
    return 'A frissítés sikertelen: $error';
  }

  @override
  String get language => 'Nyelv';

  @override
  String get languageSubtitle => 'Az alkalmazás nyelve';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHungarian => 'Magyar';

  @override
  String get libraryQuestion => 'Hol tárolja a Calibre Touch a könyveidet?';

  @override
  String get usingDefaultLocation => 'Alapértelmezett hely használatban:';

  @override
  String get usingCustomFolder => 'Egyéni mappa használatban:';

  @override
  String get loading => 'Betöltés…';

  @override
  String get chooseFolder => 'Mappa választása';

  @override
  String get useDefault => 'Alapértelmezett';

  @override
  String get darkTheme => 'Sötét téma';

  @override
  String get darkThemeSubtitle => 'Váltás világos és sötét megjelenés között';

  @override
  String get storageNeeded =>
      'Egyéni mappa használatához tárhely-hozzáférés szükséges.';

  @override
  String get storageRestricted =>
      'A tárhely-hozzáférés korlátozott ezen az eszközön.';

  @override
  String get storageDenied =>
      'A tárhely-hozzáférés elutasítva. Engedélyezd az alkalmazás beállításaiban.';

  @override
  String folderPickerError(String error) {
    return 'Nem sikerült megnyitni a mappaválasztót: $error';
  }

  @override
  String get back => 'Vissza';

  @override
  String get next => 'Tovább';

  @override
  String get getStarted => 'Kezdjük';

  @override
  String get welcome => 'Üdvözöl a Calibre Touch';

  @override
  String get onboardingIntro =>
      'Calibre könyvtárolvasó érintőképernyős eszközökre.';

  @override
  String get onboardingStandalone =>
      'A Calibre Touch önálló e-könyvtár-kezelőként is működik. Nem kompatibilis a Calibre-rel.';

  @override
  String get allSet => 'Minden kész!';

  @override
  String get allSetDetails =>
      'A könyvtárad és a megjelenés beállítva. Ezeket bármikor módosíthatod a menüből.';

  @override
  String errorMessage(String message) {
    return 'Hiba: $message';
  }

  @override
  String get read => 'Olvasás';

  @override
  String get readerContents => 'Tartalomjegyzék';

  @override
  String get readerSettings => 'Olvasási beállítások';

  @override
  String get readerFontSize => 'Betűméret';

  @override
  String get readerLineSpacing => 'Sorköz';

  @override
  String get readerTheme => 'Oldal színe';

  @override
  String get readerThemeLight => 'Világos';

  @override
  String get readerThemeSepia => 'Szépia';

  @override
  String get readerThemeDark => 'Sötét';

  @override
  String get readerThemeAuto => 'Automatikus';

  @override
  String get readerDarkMode => 'Sötét mód';

  @override
  String get readerLightMode => 'Világos mód';

  @override
  String get readerPreviousChapter => 'Előző fejezet';

  @override
  String get readerNextChapter => 'Következő fejezet';

  @override
  String readerChapterOf(int current, int total) {
    return '$current. fejezet / $total';
  }

  @override
  String readerOpenError(String error) {
    return 'Nem sikerült megnyitni a könyvet: $error';
  }

  @override
  String readerUnsupported(String format) {
    return 'A beépített olvasó csak EPUB könyveket tud megnyitni (ez $format).';
  }

  @override
  String get readerZoom => 'Nagyítás';

  @override
  String get readerZoomIn => 'Nagyítás';

  @override
  String get readerZoomOut => 'Kicsinyítés';

  @override
  String get readerPreviousPage => 'Előző oldal';

  @override
  String get readerNextPage => 'Következő oldal';

  @override
  String readerPageOf(int page, int count) {
    return '$page. oldal / $count';
  }

  @override
  String get openFolder => 'Mappa megnyitása';

  @override
  String folderNotFound(String path) {
    return 'A mappa nem található: $path';
  }

  @override
  String folderOpenFailed(String path) {
    return 'Nem sikerült megnyitni a mappát: $path';
  }

  @override
  String get builtInReader => 'Beépített olvasó';

  @override
  String get builtInReaderOn =>
      'Az EPUB és PDF könyvek a Calibre Touch-ban nyílnak meg';

  @override
  String get builtInReaderOff =>
      'Az EPUB és PDF könyvek a rendszer alapértelmezett alkalmazásában nyílnak meg';

  @override
  String get libraryEmpty => 'Ebben a könyvtárban még nincsenek könyvek.';

  @override
  String libraryLocation(String path) {
    return 'Könyvtár mappa: $path';
  }

  @override
  String get libraryNeedsStorage =>
      'A Calibre Touch nem fér hozzá ehhez a mappához. Engedélyezd a „Hozzáférés az összes fájlhoz” jogosultságot a könyvek megjelenítéséhez.';

  @override
  String libraryLoadError(String error) {
    return 'Nem sikerült megnyitni a könyvtárat: $error';
  }

  @override
  String get grantAccess => 'Hozzáférés engedélyezése';

  @override
  String get retry => 'Újra';

  @override
  String get continueReading => 'Olvasás folytatása';

  @override
  String get noRecentBook => 'Még nem nyitottál meg könyvet';

  @override
  String get published => 'Megjelenés';

  @override
  String get dateNotSet => 'Nincs megadva';

  @override
  String get clearDate => 'Dátum törlése';

  @override
  String get languages => 'Nyelvek';

  @override
  String get languagesHint => 'hun, eng';

  @override
  String get identifiers => 'Azonosítók';

  @override
  String get identifiersHint => 'isbn:9781234567897, goodreads:123';

  @override
  String unknownLanguage(String value) {
    return 'Ismeretlen nyelv: $value';
  }

  @override
  String invalidIdentifier(String value) {
    return 'Hibás azonosító: $value';
  }
}
