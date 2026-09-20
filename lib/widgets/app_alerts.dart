import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/models/models.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';

@immutable
class AppAlerts {
  static FileService fileService = FileService();

  const AppAlerts._();

  static displaySnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: buttoncolor,
        content: Text(
          style: const TextStyle(color: Colors.white),
          message,
        ),
      ),
    );
  }

  static Future<void> showAlertDeleteDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Book book,
  }) async {
    Widget cancelButton = TextButton(
      child: const Text(
        'NO',
        style: TextStyle(color: buttoncolor),
      ),
      onPressed: () => context.pop(),
    );
    Widget deleteButton = TextButton(
      onPressed: () async {
        // Files first; keep the DB entry if they can't be deleted.
        final error = await fileService.deleteBookFolder(book.path);
        if (error != null) {
          // ignore: use_build_context_synchronously
          displaySnackbar(context, 'Could not delete the book files: $error');
          // ignore: use_build_context_synchronously
          context.pop();
          return;
        }
        await ref
            .read<BookNotifier>(booksProvider.notifier)
            .deleteBook(book)
            .then(
          (value) {
            displaySnackbar(
              // ignore: use_build_context_synchronously
              context,
              'Book deleted successfully',
            );

            ref.read(selectedBookProvider.notifier).resetSelectedBook();
            // ignore: use_build_context_synchronously
            context.pop();
          },
        );
      },
      child: const Text('YES', style: TextStyle(color: buttoncolor)),
    );

    AlertDialog alert = AlertDialog(
      title: const Text('Are you sure you want to delete this book?',
          style: TextStyle(color: buttoncolor)),
      actions: [
        deleteButton,
        cancelButton,
      ],
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }
}
