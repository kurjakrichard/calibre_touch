import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../pages/pdf_reader_page.dart';
import '../pages/reader_page.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'app_alerts.dart';
import 'responsive.dart';

/// Tap / menu behaviour shared by every book view (grid, lists, tables),
/// so all views react the same way.
@immutable
class BookActions {
  const BookActions._();

  /// Single tap: select the book. On phones the details page opens; on
  /// tablet/desktop the details panel next to the list updates.
  static void select(BuildContext context, WidgetRef ref, Book book) {
    ref.read(selectedBookProvider.notifier).setSelectedBook(book);
    if (ResponsiveWidget.isMobile(context)) {
      context.pushNamed(Routes.bookDetails.name);
    }
  }

  /// Whether [book] opens in one of the built-in readers (EPUB or PDF).
  /// False when the user chose the platform's default app in Settings
  /// ([useBuiltIn] = the value of [useBuiltInReaderProvider]).
  static bool canReadInApp(Book book, {required bool useBuiltIn}) =>
      useBuiltIn && (ReaderPage.canRead(book) || PdfReaderPage.canRead(book));

  /// Opens [book]: EPUB and PDF books in the built-in readers (unless the
  /// user turned them off in Settings), anything else in the system's
  /// default app.
  static Future<void> open(
      BuildContext context, WidgetRef ref, Book book) async {
    ref.read(selectedBookProvider.notifier).setSelectedBook(book);
    if (ref.read(useBuiltInReaderProvider)) {
      if (ReaderPage.canRead(book)) {
        context.pushNamed(Routes.reader.name);
        return;
      }
      if (PdfReaderPage.canRead(book)) {
        context.pushNamed(Routes.pdfReader.name);
        return;
      }
    }
    final fs = FileService();
    fs.openFile(await fs.bookFilePath(
      path: book.path,
      filename: book.filename,
      // Calibre stores the format upper-case (EPUB) but the files on disk
      // are lower-case (.epub) - matters on case-sensitive Android.
      format: book.format.toLowerCase(),
      customPath: ref.read(pathProvider),
    ));
  }

  /// Shows the folder of [book] (book file + cover.jpg) in the system file
  /// manager.
  static Future<void> openFolder(
      BuildContext context, WidgetRef ref, Book book) async {
    final l10n = context.l10n;
    final fs = FileService();
    final folder = await fs.bookFolderPath(
      path: book.path,
      customPath: ref.read(pathProvider),
    );
    if (!await Directory(folder).exists()) {
      if (context.mounted) {
        AppAlerts.displaySnackbar(context, l10n.folderNotFound(folder));
      }
      return;
    }
    if (!await fs.openFolder(folder) && context.mounted) {
      AppAlerts.displaySnackbar(context, l10n.folderOpenFailed(folder));
    }
  }

  /// Double tap / long press: Open, Edit, Details, Delete.
  static void showMenu(BuildContext context, WidgetRef ref, Book book) {
    ref.read(selectedBookProvider.notifier).setSelectedBook(book);
    final l10n = context.l10n;

    Widget option(String label, VoidCallback onPressed) => SimpleDialogOption(
          child: TextButton(
            onPressed: onPressed,
            child: Text(label,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.start),
          ),
        );

    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        children: [
          option(
              canReadInApp(book,
                      useBuiltIn: ref.read(useBuiltInReaderProvider))
                  ? l10n.read
                  : l10n.open, () {
            Navigator.of(dialogContext).pop();
            open(context, ref, book);
          }),
          option(l10n.edit, () {
            Navigator.of(dialogContext).pop();
            context.pushNamed(Routes.updateBook.name);
          }),
          option(l10n.details, () {
            Navigator.of(dialogContext).pop();
            context.pushNamed(Routes.bookDetails.name);
          }),
          option(l10n.delete, () {
            Navigator.of(dialogContext).pop();
            AppAlerts.showAlertDeleteDialog(
                context: context, ref: ref, book: book);
          }),
        ],
      ),
    );
  }
}
