import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:remove_diacritic/remove_diacritic.dart';
import '../data/data_export.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

class UpdateBook extends ConsumerStatefulWidget {
  static UpdateBook builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const UpdateBook();
  const UpdateBook({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _UpdateBookScreenState();
}

class _UpdateBookScreenState extends ConsumerState<UpdateBook> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final FileService fileService = FileService();

  /// The book as it was when this page opened. Never changes while editing,
  /// so old/new paths can't get mixed up by provider rebuilds.
  Book? _original;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _original = ref.read(selectedBookProvider);
    final book = _original;
    if (book != null) {
      _titleController.text = book.title;
      _authorController.text = book.author;
      _descriptionController.text = book.description;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_original == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Update book')),
        body: const Center(child: Text('Nincs könyv kiválasztva')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Update book',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommonTextField(
                hintText: 'Title',
                title: 'Title',
                controller: _titleController,
              ),
              const Gap(30),
              CommonTextField(
                hintText: 'Author',
                title: 'Author',
                controller: _authorController,
              ),
              const Gap(30),
              const SelectDateTime(),
              const Gap(30),
              CommonTextField(
                hintText: 'Description',
                title: 'Description',
                maxLines: 6,
                controller: _descriptionController,
              ),
              const Gap(30),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _updateBook,
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Save',
                        ),
                      ),
                    ),
                  ),
                  const Gap(16),
                  SizedBox(
                    width: 120,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _deleteBook,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Delete'),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(30),
            ],
          ),
        ),
      ),
    );
  }

  /// Makes a value safe to use as a folder/file name.
  String _safe(String value) => removeDiacritics(value)
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim();

  void _message(String text) {
    if (mounted) AppAlerts.displaySnackbar(context, text);
  }

  Future<bool> _confirmDelete(Book book) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Are you sure you want to delete this book?',
          style: TextStyle(color: buttoncolor),
        ),
        content: Text(
          '"${book.title}" will be removed from the library and its file '
          'will be deleted from disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('NO', style: TextStyle(color: buttoncolor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('YES', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteBook() async {
    final book = _original;
    if (book == null || _saving) return;
    if (!await _confirmDelete(book)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      // 1) Files first. If they can't be deleted (book open in a reader,
      //    OneDrive lock, ...) stop here and keep the DB entry, so the
      //    library and the disk never get out of sync.
      final error = await fileService.deleteBookFolder(book.path);
      if (error != null) {
        _message('Could not delete the book files: $error');
        return;
      }

      // 2) Only then remove the database entry.
      await ref.read(booksProvider.notifier).deleteBook(book);
      await ref.read(selectedBookProvider.notifier).resetSelectedBook();

      _message('Book deleted successfully');
      if (mounted) context.goNamed(Routes.home.name);
    } catch (e, st) {
      debugPrint('Delete failed: $e\n$st');
      _message('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateBook() async {
    final original = _original;
    if (original == null || _saving) return;

    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty) return _message('Title cannot be empty');
    if (author.isEmpty) return _message('Author cannot be empty');

    final safeTitle = _safe(title);
    final safeAuthor = _safe(author);
    if (safeTitle.isEmpty ||
        safeAuthor.isEmpty ||
        safeTitle == '.' ||
        safeTitle == '..' ||
        safeAuthor == '.' ||
        safeAuthor == '..') {
      return _message('Title or author contains invalid characters');
    }

    setState(() => _saving = true);
    try {
      var newPath = '$safeAuthor/$safeTitle';
      var newFilename = '$safeAuthor - $safeTitle';
      var notice = 'Update book successfully';

      final oldFile = await fileService.bookFilePath(
        path: original.path,
        filename: original.filename,
        format: original.format,
      );
      final newFile = await fileService.bookFilePath(
        path: newPath,
        filename: newFilename,
        format: original.format,
      );

      // 1) Move the file FIRST, and only if the location really changes.
      if (!p.equals(oldFile, newFile)) {
        if (await fileService.fileExists(oldFile)) {
          await fileService.moveBookFile(from: oldFile, to: newFile);
        } else if (await fileService.fileExists(newFile)) {
          // An earlier attempt already moved the file: just fix the DB.
        } else {
          // File is not where the DB says it is: save the metadata only and
          // keep the old location, so the DB never points to a made-up path.
          newPath = original.path;
          newFilename = original.filename;
          notice = 'Saved, but the book file was not found at: $oldFile';
        }
      }

      // 2) Only then update the database.
      final book = original.copyWith(
        title: title,
        author: author,
        path: newPath,
        filename: newFilename,
        last_modified: DateFormat.yMMMd().format(ref.read(dateProvider)),
        description: description,
      );
      await ref.read(booksProvider.notifier).updateBook(book);
      await ref.read(selectedBookProvider.notifier).setSelectedBook(book);

      _message(notice);
      if (mounted) context.goNamed(Routes.home.name);
    } catch (e, st) {
      debugPrint('Update failed: $e\n$st');
      _message('Update failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
