# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Calibre Touch is a Flutter app (Android + Windows) that works as a Calibre-compatible ebook library and reader for touchscreens. It reads and writes a real Calibre library folder (`metadata.db` + `Author/Title (id)/` book folders + `metadata.opf` + `cover.jpg`), so desktop Calibre must still open a library after this app has edited it. UI languages are English and Hungarian.

## Commands

```bash
flutter pub get                               # also regenerates l10n (pubspec has generate: true)
flutter analyze
flutter test
flutter test test/metadata_test.dart          # single file
flutter test test/metadata_test.dart --plain-name "title sort"   # single test
flutter run -d windows                        # or an Android device id
```

Release builds use the `.bat` scripts in the repo root:
- `build_android.bat`: split-per-ABI release APKs, obfuscated, with symbols in `build\debug-info`.
- `build_appbundle.bat`: Play Store `.aab`. Needs `android\key.properties` and the upload keystore. Keep `build\debug-info` for every uploaded version.
- `build_msix.bat`: Microsoft Store MSIX via `dart run msix:create --store`. Raise `msix_version` in `pubspec.yaml` for each upload (the last number stays 0).

Other notes:
- Windows builds need Developer Mode turned on because pdfrx uses symlinks.
- After changing the `flutter_native_splash` section of `pubspec.yaml`, run `dart run flutter_native_splash:create`.
- For each store upload, bump `version:` in `pubspec.yaml`. The build number after `+` must always increase.

`test_books/` holds sample files in each supported format (odt, rtf, mobi with HUFF compression, txt, docx, fb2) for manual testing.

## Architecture

Data flows through these layers: **Riverpod providers → `BookNotifier` → `BookRepository` → `BookDatasource` (sqlite) + `FileService` (files on disk)**.

- **Library folder is the root of the provider graph.** `pathProvider` (backed by SharedPreferences through `SharedUtility`) holds the user's custom library path, with `''` meaning the default `<documents>/ebooks`. `bookDatasourceProvider` *watches* it, so changing the folder disposes the old `BookDatasource`, which closes the DB. The repository and `BookNotifier` then rebuild. Never read the library path from SharedPreferences directly. `FileService.libraryRoot(customPath:)` is the one place that resolves it. `BookNotifier` uses a `_generation` counter to drop results from loads that started against the previous library.
- **`lib/data/datasource/book_datasource.dart`** is the core and the largest file. It creates and maintains the real Calibre schema (normalized tables, link tables, triggers, FTS5) and maps the flat `Book` model onto it. Its class doc comment lists the field mapping. Rules that must not be broken:
  - Always open through the `sqflite_common_ffi` factory with the bundled SQLite from `sqlite3_flutter_libs`. Android's system SQLite often lacks FTS5, which Calibre's schema needs.
  - Calibre's triggers call the `title_sort()`/`uuid4()` SQL functions, which plain sqlite doesn't have. Every write to `books` drops those triggers first and recreates them afterwards. `sort` and `uuid` are computed in Dart (see `lib/metadata/calibre.dart`).
  - `calibreSchemaVersion` (`PRAGMA user_version`) may only ever be raised, never lowered. A wrong value makes desktop Calibre replay schema upgrades and offer to restore the database. Keep it in sync with the schema SQL and `_upgradeSchema`.
  - App-only fields (`price`, `cover_image`) are stored as rows in `identifiers`, so the schema doesn't need changes for them.
- **Metadata (`lib/metadata/`)**: `MetadataReaders.read(path)` picks a `MetadataReader` by file extension (EPUB, PDF, MOBI/AZW3, TXT, DOCX, ODT, RTF, FB2). Parsing runs in `Isolate.run`. If a format can't be parsed, the reader falls back to the file name, so it never throws. `opf_writer.dart` writes Calibre's per-book `metadata.opf`. `opf_library_scan.dart` reads them back to rebuild a damaged `metadata.db` (see `widgets/library_rebuild_dialog.dart`).
- **Readers**: PDF opens in `PdfReaderPage` (pdfrx/PDFium). Every other format is converted into an in-memory `EpubDocument` and shown by `ReaderPage` through `flutter_widget_from_html_core`. `lib/utils/book_documents.dart` registers the format→parser mapping, and adding a format there is enough, because Settings and `ReaderPage.canRead` follow it. Office formats (DOCX, ODT, RTF) produce `DocBlock`s that `document_builder.dart` turns into chapters, a TOC and footnotes.
- **`packages/dart_mobi`** is a vendored, patched copy of the pub package (LGPL-3.0). Its many bug fixes are listed in `packages/dart_mobi/CHANGELOG.md`, so do not replace it with the pub.dev version.
- **Incoming files** (`lib/utils/incoming_files.dart`): Android "Open with" and Share intents, plus Windows command-line paths. A second Windows instance forwards its files to the running one (`windows/runner/main.cpp`) over the `calibre_touch/incoming_files` method channel. The home page adds these files to the library.
- **Routing** (`lib/config/routes/`): go_router with a single navigator key. The start screen (onboarding, splash on desktop, home on mobile) is decided once in `routesProvider`. Don't wrap `/home` in another `/home` route, because that caused `/home/home/...` duplication. The reader routes sit outside `/home`.
- **Localization**: edit `lib/l10n/app_en.arb` (the template) and `app_hu.arb`. The `app_localizations*.dart` files are generated. Access strings with `context.l10n`.
- Folders export through barrel files (`utils.dart`, `providers.dart`, `pages.dart`, `metadata.dart`, `data_export.dart`). Import the barrel rather than individual files.
