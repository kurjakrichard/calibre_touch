import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:remove_diacritic/remove_diacritic.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
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
  final TextEditingController _publisherController = TextEditingController();
  final TextEditingController _seriesController = TextEditingController();
  final TextEditingController _seriesIndexController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final FileService fileService = FileService();

  /// The book as it was when this page opened. Never changes while editing,
  /// so old/new paths can't get mixed up by provider rebuilds.
  Book? _original;

  /// Plain-text version of the description when the page opened. If the
  /// user doesn't touch it, the original HTML (with its formatting) is kept.
  String _initialDescriptionText = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _original = ref.read(selectedBookProvider);
    final book = _original;
    if (book != null) {
      _titleController.text = book.title;
      _authorController.text = book.author;
      _publisherController.text = book.publisher;
      _seriesController.text = book.series;
      _seriesIndexController.text = Book.formatSeriesIndex(book.series_index);
      _tagsController.text = book.tagList.join(', ');
      // comments.text is HTML - edit it as plain text.
      _descriptionController.text = HtmlText.toPlainText(book.description);
      _initialDescriptionText = _descriptionController.text;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _publisherController.dispose();
    _seriesController.dispose();
    _seriesIndexController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_original == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.updateBook)),
        body: Center(child: Text(context.l10n.noBookSelected)),
      );
    }

    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.updateBook),
        actions: [
          IconButton(
            tooltip: l10n.deleteBook,
            icon: const Icon(Icons.delete),
            onPressed: _saving ? null : _deleteBook,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommonTextField(
                hintText: l10n.title,
                title: l10n.title,
                controller: _titleController,
              ),
              const Gap(30),
              CommonTextField(
                hintText: l10n.author,
                title: l10n.author,
                controller: _authorController,
              ),
              const Gap(30),
              CommonTextField(
                hintText: l10n.publisher,
                title: l10n.publisher,
                controller: _publisherController,
              ),
              const Gap(30),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CommonTextField(
                      hintText: l10n.series,
                      title: l10n.series,
                      controller: _seriesController,
                    ),
                  ),
                  const Gap(16),
                  SizedBox(
                    width: 90,
                    child: CommonTextField(
                      hintText: '1',
                      title: l10n.seriesNumber,
                      controller: _seriesIndexController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
              const Gap(30),
              CommonTextField(
                hintText: l10n.tagsHint,
                title: l10n.tagsCommaSeparated,
                controller: _tagsController,
              ),
              const Gap(30),
              const SelectDateTime(),
              const Gap(30),
              CommonTextField(
                hintText: l10n.description,
                title: l10n.description,
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
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(l10n.save),
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
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          l10n.deleteConfirmTitle,
          style: const TextStyle(color: buttoncolor),
        ),
        content: Text(l10n.deleteConfirmContent(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.no, style: const TextStyle(color: buttoncolor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.yes, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteBook() async {
    final book = _original;
    if (book == null || _saving) return;
    final l10n = context.l10n;
    if (!await _confirmDelete(book)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      // 1) Files first. If they can't be deleted (book open in a reader,
      //    OneDrive lock, ...) stop here and keep the DB entry, so the
      //    library and the disk never get out of sync.
      final error = await fileService.deleteBookFolder(
        book.path,
        customPath: ref.read(pathProvider),
      );
      if (error != null) {
        _message(l10n.couldNotDeleteFiles(error));
        return;
      }

      // 2) Only then remove the database entry.
      await ref.read(booksProvider.notifier).deleteBook(book);
      await ref.read(selectedBookProvider.notifier).resetSelectedBook();

      _message(l10n.bookDeleted);
      if (mounted) context.goNamed(Routes.home.name);
    } catch (e, st) {
      debugPrint('Delete failed: $e\n$st');
      _message(l10n.deleteFailed('$e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateBook() async {
    final original = _original;
    if (original == null || _saving) return;
    final l10n = context.l10n;

    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final descriptionText = _descriptionController.text.trim();
    final description = descriptionText == _initialDescriptionText.trim()
        ? original.description
        : HtmlText.toHtml(descriptionText);

    if (title.isEmpty) return _message(l10n.titleEmpty);
    if (author.isEmpty) return _message(l10n.authorEmpty);

    final publisher = _publisherController.text.trim();
    final series = _seriesController.text.trim();
    final tags = Book.splitTags(_tagsController.text).join(', ');
    final indexText = _seriesIndexController.text.trim().replaceAll(',', '.');
    final seriesIndex = indexText.isEmpty ? 1.0 : double.tryParse(indexText);
    if (seriesIndex == null || seriesIndex < 0) {
      return _message(l10n.seriesNumberInvalid);
    }

    final safeTitle = _safe(title);
    final safeAuthor = _safe(author);
    if (safeTitle.isEmpty ||
        safeAuthor.isEmpty ||
        safeTitle == '.' ||
        safeTitle == '..' ||
        safeAuthor == '.' ||
        safeAuthor == '..') {
      return _message(l10n.invalidCharacters);
    }

    setState(() => _saving = true);
    try {
      var newPath = '$safeAuthor/$safeTitle';
      var newFilename = '$safeAuthor - $safeTitle';
      var notice = l10n.bookUpdated;

      final customPath = ref.read(pathProvider);
      final oldFile = await fileService.bookFilePath(
        path: original.path,
        filename: original.filename,
        format: original.format,
        customPath: customPath,
      );
      final newFile = await fileService.bookFilePath(
        path: newPath,
        filename: newFilename,
        format: original.format,
        customPath: customPath,
      );

      // 1) Move the file FIRST, and only if the location really changes.
      if (!p.equals(oldFile, newFile)) {
        if (await fileService.fileExists(oldFile)) {
          await fileService.moveBookFile(
              from: oldFile, to: newFile, customPath: customPath);
          // cover.jpg lives in the same folder - bring it along.
          await fileService.moveCover(
              fromPath: original.path, toPath: newPath, customPath: customPath);
        } else if (await fileService.fileExists(newFile)) {
          // An earlier attempt already moved the file: just fix the DB.
          await fileService.moveCover(
              fromPath: original.path, toPath: newPath, customPath: customPath);
        } else {
          // File is not where the DB says it is: save the metadata only and
          // keep the old location, so the DB never points to a made-up path.
          newPath = original.path;
          newFilename = original.filename;
          notice = l10n.savedFileNotFound(oldFile);
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
        publisher: publisher,
        series: series,
        series_index: seriesIndex,
        tags: tags,
      );
      await ref.read(booksProvider.notifier).updateBook(book);
      await ref.read(selectedBookProvider.notifier).setSelectedBook(book);

      _message(notice);
      if (mounted) context.goNamed(Routes.home.name);
    } catch (e, st) {
      debugPrint('Update failed: $e\n$st');
      _message(l10n.updateFailed('$e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
