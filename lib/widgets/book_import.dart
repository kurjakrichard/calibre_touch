import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../metadata/metadata.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'app_alerts.dart';
import 'book_actions.dart';

/// What to do with a file whose book is already in the library.
enum _DuplicateChoice { existing, addFormat, addNew }

/// Outcome of importing one file: the library book it ended up as (or the
/// existing one the user picked) and the format to open.
class _ImportResult {
  final Book book;
  final String? format;
  final String? message;
  final bool added;
  const _ImportResult(this.book, this.format, {this.message, this.added = false});
}

/// Adding book files to the library - shared by the "+" button and files
/// opened with Calibre Touch from other apps (IncomingFiles).
///
/// Calibre Touch is a library manager: a file is always copied into the
/// library first and the LIBRARY copy is opened, never the original file.
/// If the book looks like one already in the library (same title and
/// author, see BookNotifier.findDuplicates) the user picks: open / show the
/// library copy, add the file to that book as another format (if it doesn't
/// have that format yet), or add it as a new book.
@immutable
class BookImport {
  const BookImport._();

  /// Waits (up to 30 s) until the library has been loaded, so duplicates
  /// can be found and the import goes into the right library.
  static Future<void> waitForLibrary(WidgetRef ref) async {
    if (ref.read(booksProvider).loaded) return;
    final done = Completer<void>();
    final sub = ref.listenManual(booksProvider, (_, next) {
      if (next.loaded && !done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    sub.close();
  }

  /// Imports [paths]. With [open] (files from other apps) a single file is
  /// opened from the library afterwards; otherwise the book is selected.
  static Future<void> importFiles(
      BuildContext context, WidgetRef ref, List<String> paths,
      {required bool open}) async {
    final l10n = context.l10n;
    _ImportResult? last;
    var added = 0;
    for (final path in paths) {
      if (!context.mounted) return;
      try {
        final result = await _importOne(context, ref, path, open: open);
        if (result == null) continue;
        last = result;
        if (result.added) added++;
      } catch (e, st) {
        debugPrint('Import failed: $e\n$st');
        if (context.mounted) {
          AppAlerts.displaySnackbar(context, l10n.importFailed('$e'));
        }
      }
    }
    final result = last;
    if (result == null || !context.mounted) return;

    if (paths.length > 1) {
      ref.read(selectedBookProvider.notifier).setSelectedBook(result.book);
      AppAlerts.displaySnackbar(context, l10n.booksAdded(added));
      return;
    }
    final message = result.message;
    if (message != null) AppAlerts.displaySnackbar(context, message);
    if (open) {
      await BookActions.open(context, ref, result.book, format: result.format);
    } else if (result.added) {
      ref.read(selectedBookProvider.notifier).setSelectedBook(result.book);
    } else {
      // "Show the library copy": select it (phones: its details page).
      BookActions.select(context, ref, result.book);
    }
  }

  static Future<_ImportResult?> _importOne(
      BuildContext context, WidgetRef ref, String path,
      {required bool open}) async {
    final l10n = context.l10n;
    final notifier = ref.read(booksProvider.notifier);
    if (!await _ensureReadable(path)) {
      throw FileSystemException('The file cannot be read', path);
    }
    final metadata = await MetadataReaders.read(path);
    debugPrint('Import $path: $metadata');
    final format = p.extension(path).replaceFirst('.', '').toUpperCase();

    final duplicates = notifier.findDuplicates(metadata);
    if (duplicates.isNotEmpty) {
      // Prefer a match that already has this format.
      final existing = duplicates.firstWhere(
          (b) => b.formatList.contains(format),
          orElse: () => duplicates.first);
      final hasFormat = existing.formatList.contains(format);
      if (!context.mounted) return null;
      final choice = await _askDuplicate(context, existing, format,
          canAddFormat: !hasFormat &&
              format.isNotEmpty &&
              existing.path.isNotEmpty &&
              existing.filename.isNotEmpty,
          open: open);
      switch (choice) {
        case null:
          return null;
        case _DuplicateChoice.existing:
          return _ImportResult(existing, hasFormat ? format : null);
        case _DuplicateChoice.addFormat:
          await notifier.addFormat(existing, path);
          final updated = _bookById(ref, existing.id) ?? existing;
          return _ImportResult(updated, format,
              message: l10n.formatAdded(format));
        case _DuplicateChoice.addNew:
          break;
      }
    }

    final id = await notifier.importFile(path, metadata);
    final book = _bookById(ref, id) ?? await notifier.getBook(id);
    if (book == null) throw StateError('The new book was not found');
    return _ImportResult(book, format, message: l10n.bookAdded, added: true);
  }

  static Book? _bookById(WidgetRef ref, int? id) => id == null
      ? null
      : ref.read(booksProvider).books.where((b) => b.id == id).firstOrNull;

  /// Android: a file opened from shared storage (not copied by the system)
  /// needs the storage permission - ask once if it can't be read.
  static Future<bool> _ensureReadable(String path) async {
    Future<bool> canRead() async {
      try {
        final raf = await File(path).open();
        await raf.close();
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await canRead()) return true;
    if (Platform.isAndroid && !await StoragePermission.isGranted) {
      await StoragePermission.ensure();
      return canRead();
    }
    return false;
  }

  static Future<_DuplicateChoice?> _askDuplicate(
      BuildContext context, Book existing, String format,
      {required bool canAddFormat, required bool open}) {
    final l10n = context.l10n;
    Widget option(BuildContext dialogContext, IconData icon, String label,
            _DuplicateChoice value) =>
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(value),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 16))),
            ],
          ),
        );

    return showDialog<_DuplicateChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.alreadyInLibrary),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(l10n.alreadyInLibraryText(
                existing.title, existing.author, existing.formatList.join(', '))),
          ),
          option(
              dialogContext,
              open ? Icons.menu_book : Icons.visibility,
              open ? l10n.openLibraryCopy : l10n.showLibraryCopy,
              _DuplicateChoice.existing),
          if (canAddFormat)
            option(dialogContext, Icons.add_circle_outline,
                l10n.addAsFormat(format), _DuplicateChoice.addFormat),
          option(dialogContext, Icons.library_add, l10n.addAsNewBook,
              _DuplicateChoice.addNew),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
