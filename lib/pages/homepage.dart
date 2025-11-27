import 'package:file_picker/file_picker.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import '../config/config.dart';
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
  PlatformFile? _pickedfile;
  // ignore: unused_field
  bool _isLoading = false;
  FileService fileService = FileService();
  var allowedExtensions = ['pdf', 'odt', 'epub', 'mobi'];

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveWidget.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Calibre Touch'),
      ),
      drawer: isDesktop ? null : const DrawerWidget(),
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

  void _insertBook(Book book, BuildContext context) async {
    await ref.read(booksProvider.notifier).addBook(book).then((value) async {
      // ignore: use_build_context_synchronously
      AppAlerts.displaySnackbar(context, 'Add book successfully');
      Book? selectedBook =
          await ref.read(booksProvider.notifier).getBook(value!);
      ref.read(selectedBookProvider.notifier).setSelectedBook(selectedBook!);
      // ignore: use_build_context_synchronously
      context.go(RouteLocation.home);
    });
  }

  Future<Book?> pickFile() async {
    Book? newBook;
    try {
      setState(() {
        _isLoading = true;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: false,
          allowedExtensions: allowedExtensions);

      if (result != null) {
        _pickedfile = result.files.first;
        // ignore: avoid_print
        print('Name: ${_pickedfile!.name}');
        // ignore: avoid_print
        print('Bytes: ${_pickedfile!.bytes}');
        // ignore: avoid_print
        print('Size: ${_pickedfile!.size}');
        // ignore: avoid_print
        print('Extension: ${_pickedfile!.extension}');
        // ignore: avoid_print
        print('Path: ${_pickedfile!.path}');
        String title = p.basenameWithoutExtension(_pickedfile!.name);
        String? authorsByTitle =
            await ref.read(booksProvider.notifier).getTitlesByTitle(title);
        if (authorsByTitle != null) {
          showDialog(
              context: context,
              builder: (_) {
                return SimpleDialog(
                  //title: const Text("Dialog Title"),
                  children: [
                    const Center(
                        child: Text(
                            'Már van ilyen könyv című könyv a könyvtárban!')),
                    const Center(child: Text('Biztos hozzáadod?')),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SimpleDialogOption(
                          child: TextButton(
                              onPressed: () {},
                              child: const Text('Igen',
                                  style: TextStyle(fontSize: 16),
                                  textAlign: TextAlign.start)),
                        ),
                        SimpleDialogOption(
                          child: TextButton(
                              onPressed: () {},
                              child: const Text('Nem',
                                  style: TextStyle(fontSize: 16),
                                  textAlign: TextAlign.start)),
                        ),
                      ],
                    ),
                  ],
                );
              });
        }
        String format = _pickedfile!.extension.toString();
        String author = 'Unknown author';
        String filename =
            '${removeDiacritics(author)} - ${removeDiacritics(title)}';
        String path = '${removeDiacritics(author)}/${removeDiacritics(title)}';
        newBook = Book(
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

        await fileService.copyFile(
            oldpath: _pickedfile!.path!,
            newpath:
                '/home/sire/Dokumentumok/ebooks/${newBook.path}/${newBook.filename}.${newBook.format}');
        //await fileService.addFile(_pickedfile);
        //fileService.openFile(_pickedfile!.path!);
      } else {
        setState(() {
          _isLoading = false;
        });
        return null;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
    }
    return newBook;
  }
}
