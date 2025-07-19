import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../data/data_export.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

class UpdateBook2 extends ConsumerStatefulWidget {
  static UpdateBook2 builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const UpdateBook2();
  const UpdateBook2({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _UpdateBookScreenState();
}

class _UpdateBookScreenState extends ConsumerState<UpdateBook2> {
  final TextEditingController _textController = TextEditingController();

  int? id;
  String? format;
  String? oldPath;
  String? oldFilename;
  // ignore: non_constant_identifier_names
  String? last_modified;
  Book? selectedBook;
  FileService fileService = FileService();

  @override
  void dispose() {
    _textController.dispose();

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    selectedBook = ref.watch(selectedBookProvider);
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    if (selectedBook != null) {
      _textController.text = selectedBook!.title;

      id = selectedBook!.id;
      format = selectedBook!.format;
      last_modified = selectedBook!.last_modified;
      oldPath = selectedBook!.path;
      oldFilename = selectedBook!.filename;
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
                controller: _textController,
              ),
              const Gap(30),
              CommonTextField(
                hintText: 'Author',
                title: 'Author',
                controller: _textController,
              ),
              const Gap(30),
              const SelectDateTime(),
              const Gap(30),
              CommonTextField(
                hintText: 'Description',
                title: 'Description',
                maxLines: 6,
                controller: _textController,
              ),
              const Gap(30),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: _updateBook,
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Save',
                    ),
                  ),
                ),
              ),
              const Gap(30),
            ],
          ),
        ),
      ),
    );
  }

  void _updateBook({String? title, String? author, String? description}) async {
    final oldBook = ref.read(selectedBookProvider);
    title = title ?? oldBook!.title;
    author = author ?? oldBook!.author;
    description = description ?? oldBook!.description;
    final date = ref.watch(dateProvider);
    String? path;
    String? filename;
    if (title.isNotEmpty) {
      path = '${removeDiacritics(author)}/${removeDiacritics(title)}';
      filename = '${removeDiacritics(author)} - ${removeDiacritics(title)}';
      final book = ref.watch(selectedBookProvider)!.copyWith(
            title: title,
            author: author,
            path: path,
            filename: filename,
            last_modified: DateFormat.yMMMd().format(date),
            description: description,
          );
      ref.read(selectedBookProvider.notifier).setSelectedBook(book);
      await ref.read(booksProvider.notifier).updateBook(book).then((value) {
        // ignore: use_build_context_synchronously
        AppAlerts.displaySnackbar(context, 'Update book successfully');
        // ignore: use_build_context_synchronously
        Navigator.popUntil(context, ModalRoute.withName('/'));
        //context.go(RouteLocation.home);
      });
      await fileService.copyFile(
          oldpath:
              '/home/sire/Dokumentumok/ebooks/$oldPath/$oldFilename.${book.format}',
          newpath:
              '/home/sire/Dokumentumok/ebooks/$path/$filename.${book.format}');
      await fileService.deleteBook('/home/sire/Dokumentumok/ebooks/$oldPath');
    } else {
      AppAlerts.displaySnackbar(context, 'Title cannot be empty');
    }
  }
}
