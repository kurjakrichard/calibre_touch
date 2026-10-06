import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/incoming_files.dart';
import '../utils/utils.dart';
import '../widgets/library_rebuild_dialog.dart';
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
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  /// The "open last book on startup" check runs only once per app run,
  /// not every time the home page is rebuilt or re-created.
  static bool _startupChecked = false;

  /// Files opened with Calibre Touch from other apps (IncomingFiles).
  StreamSubscription<void>? _incomingSub;
  bool _handlingIncoming = false;

  /// Watches for a damaged metadata.db (see [_offerRebuild]).
  ProviderSubscription<bool>? _damagedSub;

  @override
  void initState() {
    super.initState();
    if (!_startupChecked) {
      _startupChecked = true;
      // Started to open a file: that book wins over "open last book".
      if (!IncomingFiles.hasPending) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _openLastBookOnStart());
      }
    }
    // metadata.db exists but can't be opened: offer to rebuild it from the
    // metadata.opf files. fireImmediately: the library may have failed to
    // load before this page was built.
    _damagedSub = ref.listenManual<bool>(
      booksProvider.select((s) => s.error?.damagedDatabase ?? false),
      (previous, damaged) {
        if (damaged && previous != true) _offerRebuild();
      },
      fireImmediately: true,
    );
    _incomingSub = IncomingFiles.onArrived.listen((_) => _handleIncoming());
    if (IncomingFiles.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleIncoming());
    }
  }

  /// "The library database is damaged - rebuild it from metadata.opf?"
  void _offerRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LibraryRebuildDialog.offer(context, ref);
    });
  }

  /// Adds files opened with Calibre Touch to the library and opens the
  /// library copy (see BookImport), one "open" / "share" action at a time.
  Future<void> _handleIncoming() async {
    if (_handlingIncoming) return;
    _handlingIncoming = true;
    try {
      while (mounted && IncomingFiles.hasPending) {
        await BookImport.waitForLibrary(ref);
        if (!mounted) break;
        final files = IncomingFiles.takeNext();
        if (files == null) break;
        try {
          await BookImport.importFiles(context, ref, files, open: true);
        } finally {
          for (final file in files) {
            await IncomingFiles.release(file);
          }
        }
      }
    } finally {
      _handlingIncoming = false;
    }
  }

  /// Settings > "Open last book on startup": once the library has loaded,
  /// opens the book last read in the built-in reader (if it still exists).
  Future<void> _openLastBookOnStart() async {
    if (!mounted || !ref.read(openLastBookOnStartProvider)) return;
    await BookImport.waitForLibrary(ref);
    if (!mounted || IncomingFiles.hasPending) return;
    final lastId = ref.read(lastReadBookProvider);
    if (lastId == null) return;
    final book = ref
        .read(booksProvider)
        .books
        .where((b) => b.id == lastId)
        .firstOrNull;
    if (book != null) BookActions.open(context, ref, book);
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _damagedSub?.close();
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
          final path = await pickFile();
          if (path != null && context.mounted) {
            await BookImport.importFiles(context, ref, [path], open: false);
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
              cursorColor: onButtonColor,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: onButtonColor),
              decoration: InputDecoration(
                // Tappable search button (same as pressing Enter).
                prefixIcon: IconButton(
                  tooltip: l10n.search,
                  icon: const Icon(Icons.search, color: onButtonColor),
                  onPressed: () => _searchNow(_searchController.text),
                ),
                hintText: l10n.searchBook,
                hintStyle: const TextStyle(color: searchHintColor),
                border: InputBorder.none,
              ),
            ),
      actions: <Widget>[
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
        const HomeMenuButton(),
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
            color: transparentColor,
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

  /// Lets the user pick a book file. Null if cancelled. (Reading the
  /// metadata and the duplicate check happen in BookImport.)
  Future<String?> pickFile() async {
    setState(() => _isLoading = true);
    try {
      // Every format Calibre knows (Formats). On Android/iOS the picker
      // filters by MIME type and drops extensions it doesn't know (mobi,
      // azw3, fb2, ...), so there any file can be picked and the extension
      // is checked afterwards.
      final mobile = defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      final picked = mobile
          ? await FilePicker.pickFile(type: FileType.any)
          : await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: Formats.extensions.toList()..sort(),
            );
      if (picked == null) return null; // user cancelled

      final sourcePath = picked.path;
      if (sourcePath == null) {
        throw Exception('The picker returned no file path');
      }
      if (!Formats.isBookFile(sourcePath)) {
        if (mounted) {
          AppAlerts.displaySnackbar(
              context, context.l10n.unsupportedFormat(picked.name));
        }
        return null;
      }
      debugPrint('Picked: ${picked.name} -> $sourcePath');
      return sourcePath;
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
