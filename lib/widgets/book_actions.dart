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

  /// Whether [book] opens in one of the built-in readers (EPUB or PDF) -
  /// true if any of its formats does. False when the user chose the
  /// platform's default app in Settings ([useBuiltIn] = the value of
  /// [useBuiltInReaderProvider]).
  static bool canReadInApp(Book book, {required bool useBuiltIn}) =>
      useBuiltIn &&
      book.formatList.any((f) => _canReadFormatInApp(book.withFormat(f)));

  static bool _canReadFormatInApp(Book book) =>
      ReaderPage.canRead(book) || PdfReaderPage.canRead(book);

  /// Opens [book] in [format] (e.g. 'PDF'). Without [format], a book with
  /// several formats asks which one first (like Calibre's "Read" button);
  /// a book with one format opens straight away.
  ///
  /// EPUB and PDF open in the built-in readers (unless the user turned
  /// them off in Settings), anything else in the system's default app.
  static Future<void> open(BuildContext context, WidgetRef ref, Book book,
      {String? format}) async {
    ref.read(selectedBookProvider.notifier).setSelectedBook(book);
    if (format == null) {
      final formats = book.formatList;
      if (formats.length > 1) {
        format = await chooseFormat(context, ref, book);
        if (format == null || !context.mounted) return;
      }
    }
    // The selected book stays as it is (its default format); only the
    // copy that is opened gets the chosen format.
    final target = book.withFormat(format);
    if (ref.read(useBuiltInReaderProvider)) {
      if (ReaderPage.canRead(target)) {
        context.pushNamed(Routes.reader.name, extra: target.format);
        return;
      }
      if (PdfReaderPage.canRead(target)) {
        context.pushNamed(Routes.pdfReader.name, extra: target.format);
        return;
      }
    }
    final fs = FileService();
    fs.openFile(await fs.bookFilePath(
      path: target.path,
      filename: target.filename,
      // Calibre stores the format upper-case (EPUB) but the files on disk
      // are lower-case (.epub) - matters on case-sensitive Android.
      format: target.format.toLowerCase(),
      customPath: ref.read(pathProvider),
    ));
  }

  /// Dialog listing the formats of [book]; returns the picked one
  /// ('EPUB', 'PDF', ...) or null if cancelled.
  static Future<String?> chooseFormat(
      BuildContext context, WidgetRef ref, Book book) {
    final l10n = context.l10n;
    final useBuiltIn = ref.read(useBuiltInReaderProvider);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.chooseFormat),
        children: [
          for (final f in book.formatList)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(f),
              child: Row(
                children: [
                  Icon(useBuiltIn && _canReadFormatInApp(book.withFormat(f))
                      ? Icons.menu_book
                      : Icons.open_in_new),
                  const SizedBox(width: 16),
                  Text(f, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
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
    final readInApp =
        canReadInApp(book, useBuiltIn: ref.read(useBuiltInReaderProvider));

    // Icon + label, left-aligned so the icons line up in one column.
    // [color] tints both (used for Delete).
    Widget option(IconData icon, String label, VoidCallback onPressed,
            {Color? color}) =>
        SimpleDialogOption(
          child: TextButton.icon(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: color,
            ),
            icon: Icon(icon),
            label: Text(label,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.start),
          ),
        );

    // The options form one block centred in the dialog: IntrinsicWidth makes
    // every button as wide as the widest one, and each is left-aligned, so
    // the icons and labels all start at the same position.
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        children: [
          Center(
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Same icons as the format chooser: built-in reader vs
                  // system app.
                  option(readInApp ? Icons.menu_book : Icons.open_in_new,
                      readInApp ? l10n.read : l10n.open, () {
                    Navigator.of(dialogContext).pop();
                    open(context, ref, book);
                  }),
                  option(Icons.edit, l10n.edit, () {
                    Navigator.of(dialogContext).pop();
                    context.pushNamed(Routes.updateBook.name);
                  }),
                  option(Icons.info_outline, l10n.details, () {
                    Navigator.of(dialogContext).pop();
                    context.pushNamed(Routes.bookDetails.name);
                  }),
                  option(Icons.delete, l10n.delete,
                      color: Theme.of(context).colorScheme.error, () {
                    Navigator.of(dialogContext).pop();
                    AppAlerts.showAlertDeleteDialog(
                        context: context, ref: ref, book: book);
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
