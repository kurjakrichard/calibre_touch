import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../metadata/calibre.dart';
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
  final TextEditingController _pubdateController = TextEditingController();
  final TextEditingController _languagesController = TextEditingController();
  final TextEditingController _identifiersController = TextEditingController();
  final FileService fileService = FileService();

  /// Publication date being edited (local date), null = none.
  DateTime? _pubdate;
  bool _pubdateChanged = false;

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
      _languagesController.text = book.languageList.join(', ');
      _identifiersController.text = book.identifierMap.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      _pubdate = book.pubdate.isEmpty
          ? null
          : DateTime.tryParse(book.pubdate)?.toLocal();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showPubdate(); // needs the locale for the date format
  }

  void _showPubdate() {
    final date = _pubdate;
    _pubdateController.text = date == null
        ? ''
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
            .format(date);
  }

  Future<void> _pickPubdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pubdate ?? now,
      firstDate: DateTime(1000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pubdate = DateTime(picked.year, picked.month, picked.day);
      _pubdateChanged = true;
      _showPubdate();
    });
  }

  void _clearPubdate() => setState(() {
        _pubdate = null;
        _pubdateChanged = true;
        _showPubdate();
      });

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _publisherController.dispose();
    _seriesController.dispose();
    _seriesIndexController.dispose();
    _tagsController.dispose();
    _pubdateController.dispose();
    _languagesController.dispose();
    _identifiersController.dispose();
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
              CommonTextField(
                hintText: l10n.dateNotSet,
                title: l10n.published,
                controller: _pubdateController,
                readOnly: true,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pubdate != null)
                      IconButton(
                        tooltip: l10n.clearDate,
                        icon: const Icon(Icons.clear),
                        onPressed: _saving ? null : _clearPubdate,
                      ),
                    IconButton(
                      tooltip: l10n.published,
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: _saving ? null : _pickPubdate,
                    ),
                  ],
                ),
              ),
              const Gap(30),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: CommonTextField(
                      hintText: l10n.languagesHint,
                      title: l10n.languages,
                      controller: _languagesController,
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: CommonTextField(
                      hintText: l10n.identifiersHint,
                      title: l10n.identifiers,
                      controller: _identifiersController,
                    ),
                  ),
                ],
              ),
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

  /// First author of an "A & B" author string ('' if none).
  static String _firstAuthor(String author) => author
      .split('&')
      .map((a) => a.trim())
      .firstWhere((a) => a.isNotEmpty, orElse: () => '');

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

    // Languages: "en, hu", "eng, hun", "English" ... -> Calibre codes.
    final languages = <String>[];
    for (final raw in _languagesController.text.split(',')) {
      if (raw.trim().isEmpty) continue;
      final code = Calibre.languageCode(raw);
      if (code == null) return _message(l10n.unknownLanguage(raw.trim()));
      if (!languages.contains(code)) languages.add(code);
    }

    // Identifiers: "isbn:978..., goodreads:123" (a bare ISBN is accepted).
    final identifiers = <String, String>{};
    for (final raw in _identifiersController.text.split(',')) {
      final item = raw.trim();
      if (item.isEmpty) continue;
      final colon = item.indexOf(':');
      final entry = colon > 0
          ? Calibre.identifier(
              item.substring(0, colon), item.substring(colon + 1))
          : Calibre.identifier(null, item);
      if (entry == null) return _message(l10n.invalidIdentifier(item));
      identifiers[entry.key] = entry.value;
    }

    // The first author decides the folder, as in Calibre.
    final firstAuthor = _firstAuthor(author);
    if (firstAuthor.isEmpty) return _message(l10n.authorEmpty);

    setState(() => _saving = true);
    var moved = false;
    try {
      var newPath = original.path;
      var newFilename = original.filename;
      var notice = l10n.bookUpdated;
      final customPath = ref.read(pathProvider);

      // 1) Calibre renames the book's folder and files when the title or
      //    first author changes: <Author>/<Title> (<id>)/<Title> - <Author>.
      //    Books added by older versions of this app (folder without
      //    " (<id>)") are moved to Calibre's layout on their first save.
      final id = original.id;
      final calibreLayout =
          id != null && original.path.endsWith(' ($id)');
      final renamed = title != original.title ||
          firstAuthor != _firstAuthor(original.author);
      if (id != null && (renamed || !calibreLayout)) {
        newPath = Calibre.bookFolder(id, title, firstAuthor);
        newFilename =
            Calibre.bookFileName(title, firstAuthor, original.format);
      }

      if (newPath != original.path || newFilename != original.filename) {
        try {
          await fileService.relocateBook(
            fromPath: original.path,
            toPath: newPath,
            fromName: original.filename,
            toName: newFilename,
            customPath: customPath,
          );
          moved = true;
        } on FileSystemException catch (e) {
          // Folder missing (or the target taken): save the metadata only and
          // keep the old location, so the DB never points to a made-up path.
          debugPrint('Book files not moved: $e');
          newPath = original.path;
          newFilename = original.filename;
          notice = l10n.savedFileNotFound(e.path ?? original.path);
        }
      }

      // 2) Only then update the database. If that fails, move the files back.
      final book = original.copyWith(
        title: title,
        author: author,
        path: newPath,
        filename: newFilename,
        last_modified: Calibre.now(),
        description: description,
        publisher: publisher,
        series: series,
        series_index: seriesIndex,
        tags: tags,
        languages: languages.join(', '),
        identifiers: Book.joinIdentifiers(identifiers),
        pubdate: !_pubdateChanged
            ? original.pubdate
            : (_pubdate == null ? '' : Calibre.formatTimestamp(_pubdate!)),
      );
      try {
        await ref.read(booksProvider.notifier).updateBook(book);
      } catch (e) {
        if (moved) {
          try {
            await fileService.relocateBook(
              fromPath: newPath,
              toPath: original.path,
              fromName: newFilename,
              toName: original.filename,
              customPath: customPath,
            );
          } catch (undoError) {
            debugPrint('Could not move the files back: $undoError');
          }
        }
        rethrow;
      }
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
