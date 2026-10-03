import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../metadata/metadata.dart';
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
  var allowedExtensions = ['pdf', 'odt', 'epub', 'mobi'];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Enter / search button: filter the books.
  void _searchNow(String value) {
    ref.read(booksProvider.notifier).search(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveWidget.isDesktop(context);

    return Scaffold(
      appBar: appBar(context, isDesktop),
      drawer: const DrawerWidget(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final picked = await pickFile();
          if (picked != null) {
            // ignore: use_build_context_synchronously
            _importBook(picked.path, picked.metadata, context);
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

  /// App bar that switches between the title and a search field.
  PreferredSizeWidget appBar(BuildContext context, bool isDesktop) {
    final l10n = context.l10n;
    return AppBar(
      automaticallyImplyLeading: !isDesktop,
      title: !_isSearching
          ? Text(l10n.appTitle)
          : TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              // Search only when typing is finished (Enter / search key),
              // not on every keystroke.
              onSubmitted: _searchNow,
              cursorColor: Colors.white,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white),
              decoration: InputDecoration(
                // Tappable search button (same as pressing Enter).
                prefixIcon: IconButton(
                  tooltip: l10n.search,
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () => _searchNow(_searchController.text),
                ),
                hintText: l10n.searchBook,
                hintStyle: const TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
            ),
      actions: <Widget>[
        const BookViewMenuButton(),
        _isSearching
            ? IconButton(
                tooltip: l10n.closeSearch,
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                  ref.read(booksProvider.notifier).clearSearch();
                },
                icon: const Icon(Icons.cancel))
            : IconButton(
                tooltip: l10n.search,
                onPressed: () {
                  setState(() {
                    _isSearching = true;
                  });
                },
                icon: const Icon(Icons.search)),
      ],
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
    return BookViewBody(count: count);
  }

  /// Adds the picked file to the library (see BookNotifier.importFile).
  Future<void> _importBook(
      String sourcePath, BookMetadata metadata, BuildContext context) async {
    final l10n = context.l10n;
    final int id;
    try {
      id = await ref
          .read(booksProvider.notifier)
          .importFile(sourcePath, metadata);
    } catch (e, st) {
      debugPrint('Import failed: $e\n$st');
      if (context.mounted) {
        AppAlerts.displaySnackbar(context, l10n.importFailed('$e'));
      }
      return;
    }
    final saved = await ref.read(booksProvider.notifier).getBook(id);
    if (saved != null) {
      ref.read(selectedBookProvider.notifier).setSelectedBook(saved);
    }
    if (context.mounted) {
      AppAlerts.displaySnackbar(context, l10n.bookAdded);
      context.go(Routes.home.path);
    }
  }

  Future<bool> _confirmDuplicate() async {
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.duplicateTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.yes),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.no),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Lets the user pick a book file and reads its metadata (title,
  /// authors, cover, ...). Null if cancelled or a duplicate was declined.
  Future<({String path, BookMetadata metadata})?> pickFile() async {
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

      final metadata = await MetadataReaders.read(sourcePath);
      debugPrint('Metadata: $metadata');

      final existing = await ref
          .read(booksProvider.notifier)
          .getTitlesByTitle(metadata.title);
      if (existing != null) {
        if (!mounted) return null;
        final add = await _confirmDuplicate(); // now WAITS for the answer
        if (!add) return null;
      }

      return (path: sourcePath, metadata: metadata);
    } catch (e, st) {
      debugPrint('Import failed: $e\n$st');
      if (mounted) {
        AppAlerts.displaySnackbar(context, context.l10n.importFailed('$e'));
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
