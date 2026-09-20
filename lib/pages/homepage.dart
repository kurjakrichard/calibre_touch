import 'package:file_picker/file_picker.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../data/data_export.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

class HomePage extends ConsumerStatefulWidget {
  static HomePage builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const HomePage();
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomePage> {
  Book? selectedBook;
  // ignore: unused_field
  bool _isLoading = false;
  FileService fileService = FileService();
  var allowedExtensions = ['pdf', 'odt', 'epub', 'mobi'];

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveWidget.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktop,
        title: const Text('Calibre Touch'),
      ),
      drawer: const DrawerWidget(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          Book? newBook = await pickFile();
          if (newBook != null) {
            // ignore: use_build_context_synchronously
            _insertBook(newBook, context);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: ResponsiveWidget(
        mobile: buildMobile(),
        tablet: buildTablet(),
        desktop: buildDesktop(),
      ),
    );
  }

  Widget buildMobile() => SafeArea(child: bookList());
  Widget buildTablet() => Row(
        children: [
          Expanded(
            flex: 2,
            child: bookList(count: 1.5),
          ),
          const VerticalDivider(
            thickness: 4,
            color: Colors.transparent,
          ),
          const Expanded(
            flex: 1,
            child: Details(),
          )
        ],
      );
  Widget buildDesktop() => Row(
        children: [
          const Expanded(
            flex: 1,
            child: DrawerWidget(),
          ),
          Expanded(
            flex: 5,
            child: bookList(count: 1.5),
          ),
          const Expanded(
            flex: 2,
            child: Details(),
          )
        ],
      );

  Widget bookList({double count = 1.0}) {
    return GridList(count: count);
  }

  Future<void> _insertBook(Book book, BuildContext context) async {
    final id = await ref.read(booksProvider.notifier).addBook(book);
    if (id == null) {
      // addBook() swallows DB errors and returns null, so report it here.
      if (context.mounted) {
        AppAlerts.displaySnackbar(context, 'Could not save book to database');
      }
      return;
    }
    final saved = await ref.read(booksProvider.notifier).getBook(id);
    if (saved != null) {
      ref.read(selectedBookProvider.notifier).setSelectedBook(saved);
    }
    if (context.mounted) {
      AppAlerts.displaySnackbar(context, 'Add book successfully');
      context.go(Routes.home.path);
    }
  }

  Future<bool> _confirmDuplicate() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text(
            'Már van ilyen című könyv a könyvtárban!\nBiztos hozzáadod?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Igen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Nem'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<Book?> pickFile() async {
    setState(() => _isLoading = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (picked == null) return null; // user cancelled

      final sourcePath = picked.path;
      if (sourcePath == null) {
        throw Exception('The picker returned no file path');
      }
      debugPrint('Picked: ${picked.name} -> $sourcePath');

      final title = p.basenameWithoutExtension(picked.name);
      final format = p.extension(picked.name).replaceFirst('.', '');

      final existing =
          await ref.read(booksProvider.notifier).getTitlesByTitle(title);
      if (existing != null) {
        if (!mounted) return null;
        final add = await _confirmDuplicate(); // now WAITS for the answer
        if (!add) return null;
      }

      const author = 'Unknown author';
      final filename = '${removeDiacritics(author)} - ${removeDiacritics(title)}';
      final path = '${removeDiacritics(author)}/${removeDiacritics(title)}';

      final book = Book(
        author: author,
        title: title,
        description: '',
        image: 'res/corel.jpg',
        last_modified: '',
        path: path,
        filename: filename,
        format: format,
        pages: 0,
        price: '',
        rating: 0,
      );

      final target = await fileService.bookFilePath(
          path: path, filename: filename, format: format);
      debugPrint('Copying to: $target');
      await fileService.copyFile(oldpath: sourcePath, newpath: target);

      return book; // only returned if the file was really copied
    } catch (e, st) {
      debugPrint('Import failed: $e\n$st');
      if (mounted) {
        AppAlerts.displaySnackbar(context, 'Import failed: $e');
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
