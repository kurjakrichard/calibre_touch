import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'reader_page.dart'
    show ReaderTheme, ReaderThemeChips, ReaderDarkModeButton;

/// Full-screen PDF reader for the selected book, the PDF twin of
/// [ReaderPage]: same page colours, same tap-to-show controls, system bars
/// hidden on phones, last page remembered.
///
/// PDF pages are fixed images, so instead of font settings there is zoom
/// (pinch, Ctrl + mouse wheel, double tap) and the page colour is applied as
/// a filter (sepia tint, or inverted for dark).
///
/// Desktop keys: Esc closes; arrows, PageUp/PageDown, Home/End and +/- are
/// handled by the viewer.
class PdfReaderPage extends ConsumerStatefulWidget {
  static Page<void> pageBuilder(BuildContext context, GoRouterState state) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        child: const PdfReaderPage(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  const PdfReaderPage({super.key});

  /// Whether the built-in PDF reader can open [book].
  static bool canRead(Book book) => book.format.toLowerCase() == 'pdf';

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

/// One line of the PDF outline (bookmarks), flattened.
class _OutlineEntry {
  const _OutlineEntry(this.title, this.dest, this.depth);
  final String title;
  final PdfDest? dest;
  final int depth;
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage>
    with WidgetsBindingObserver {
  /// Viewer background before the colour filter is applied (grey around
  /// the pages; becomes dark grey when inverted).
  static const Color _viewerBackground = Color(0xFFDDDDDD);

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _controller = PdfViewerController();

  late final SharedPreferences _prefs;
  late final String _positionKey;
  Book? _book;
  String? _path;
  Object? _error;

  int _page = 1;
  int _pageCount = 0;
  List<_OutlineEntry> _outline = const [];
  Timer? _saveTimer;

  bool _showControls = false;
  /// Picked page colour; null = Auto (follows the app's light/dark theme).
  ReaderTheme? _themeChoice;

  /// The app's theme mode, refreshed in [build].
  String _appMode = 'light';

  ReaderTheme get _theme => ReaderTheme.resolve(_themeChoice, _appMode);

  void _setThemeChoice(ReaderTheme? choice) {
    setState(() => _themeChoice = choice);
    ReaderTheme.saveChoice(_prefs, choice);
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _prefs = ref.read(sharedPreferencesProvider);
    _book = ref.read(selectedBookProvider);
    _positionKey = 'pdfPosition:${ref.read(pathProvider)}|'
        '${_book?.path}/${_book?.filename}';
    _page = _prefs.getInt(_positionKey) ?? 1;
    _themeChoice = ReaderTheme.loadChoice(_prefs);
    _appMode = ref.read(modeProvider);

    final book = _book;
    // Remember it for the drawer's "Continue reading" button (after this
    // frame: providers can't be modified while the widget tree builds).
    if (book != null && PdfReaderPage.canRead(book)) {
      Future.microtask(() {
        if (mounted) ref.read(lastReadBookProvider.notifier).set(book);
      });
    }
    if (book != null && PdfReaderPage.canRead(book)) _resolvePath(book);
    _applySystemUi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _savePosition();
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _savePosition();
    }
  }

  Future<void> _resolvePath(Book book) async {
    try {
      final path = await FileService().bookFilePath(
        path: book.path,
        filename: book.filename,
        // Calibre stores the format upper-case ('PDF'), the file extension
        // is lower-case.
        format: book.format.toLowerCase(),
        customPath: ref.read(pathProvider),
      );
      if (!await File(path).exists()) {
        throw FileSystemException('File not found', path);
      }
      if (mounted) setState(() => _path = path);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  // ---- position ----

  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    setState(() => _page = page);
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 2), _savePosition);
  }

  void _savePosition() {
    if (_path == null) return;
    _prefs.setInt(_positionKey, _page);
  }

  Future<void> _onViewerReady(
      PdfDocument document, PdfViewerController controller) async {
    setState(() => _pageCount = document.pages.length);
    try {
      final nodes = await document.loadOutline();
      final entries = <_OutlineEntry>[];
      void walk(List<PdfOutlineNode> list, int depth) {
        for (final node in list) {
          final title = node.title.trim();
          if (title.isNotEmpty) {
            entries.add(_OutlineEntry(title, node.dest, depth));
          }
          walk(node.children, depth + 1);
        }
      }

      walk(nodes, 0);
      if (mounted) setState(() => _outline = entries);
    } catch (e) {
      debugPrint('PDF outline could not be loaded: $e');
    }
  }

  void _goToPage(int page) {
    if (!_controller.isReady) return;
    final target = page.clamp(1, _controller.pageCount);
    _controller.goToPage(pageNumber: target);
  }

  // ---- controls ----

  void _applySystemUi() {
    if (!_isMobile) return;
    SystemChrome.setEnabledSystemUIMode(
      _showControls ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _applySystemUi();
  }

  void _close() {
    _savePosition();
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(Routes.home.name);
    }
  }

  bool _onTap(BuildContext context, PdfViewerController controller,
      PdfViewerGeneralTapHandlerDetails details) {
    switch (details.type) {
      case PdfViewerGeneralTapType.tap:
        _toggleControls();
        return true;
      case PdfViewerGeneralTapType.doubleTap:
        controller.zoomUpOnLocalPosition(
          localPosition: details.localPosition,
          loop: true,
        );
        return true;
      default:
        return false;
    }
  }

  /// Colour filter that turns white pages into the chosen page colour.
  ColorFilter? get _pageFilter {
    switch (_theme) {
      case ReaderTheme.light:
        return null;
      case ReaderTheme.sepia:
        return ColorFilter.mode(ReaderTheme.sepia.background, BlendMode.multiply);
      case ReaderTheme.dark:
        // Invert: white page -> black, black text -> white.
        return const ColorFilter.matrix(<double>[
          -0.85, 0, 0, 0, 230, //
          0, -0.85, 0, 0, 230, //
          0, 0, -0.85, 0, 230, //
          0, 0, 0, 1, 0, //
        ]);
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _theme.bar,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final l10n = context.l10n;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.readerTheme, style: TextStyle(color: _theme.text)),
                  const SizedBox(height: 8),
                  ReaderThemeChips(
                    choice: _themeChoice,
                    onChanged: (choice) {
                      _setThemeChoice(choice);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.readerZoom, style: TextStyle(color: _theme.text)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.outlined(
                        tooltip: l10n.readerZoomOut,
                        icon: Icon(Icons.zoom_out, color: _theme.text),
                        onPressed: () => _controller.zoomDown(),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: l10n.readerZoomIn,
                        icon: Icon(Icons.zoom_in, color: _theme.text),
                        onPressed: () => _controller.zoomUp(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    // Auto page colour follows the app theme, also if it changes meanwhile.
    _appMode = ref.watch(modeProvider);
    final l10n = context.l10n;
    final book = _book;
    final path = _path;

    Widget body;
    if (book == null) {
      body = _buildMessage(l10n.noBookSelected);
    } else if (!PdfReaderPage.canRead(book)) {
      body = _buildMessage(l10n.readerUnsupported(book.format));
    } else if (_error != null) {
      body = _buildMessage(l10n.readerOpenError('$_error'));
    } else if (path == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        children: [
          Positioned.fill(child: _buildViewer(path)),
          _buildTopBar(book),
          _buildBottomBar(),
        ],
      );
    }

    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: buttoncolor,
          brightness: _theme.brightness,
        ),
        iconTheme: IconThemeData(color: _theme.text),
        drawerTheme: DrawerThemeData(backgroundColor: _theme.bar),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _showControls ? _toggleControls() : _close(),
        },
        // The viewer takes keyboard focus itself (keyHandlerParams below);
        // Esc bubbles up to here.
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: _theme.background,
          drawer: _outline.isEmpty ? null : _buildOutline(book!),
          body: body,
        ),
      ),
    );
  }

  Widget _buildMessage(String message) => SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: context.l10n.back,
                icon: Icon(Icons.arrow_back, color: _theme.text),
                onPressed: _close,
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _theme.text, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildViewer(String path) {
    final viewer = PdfViewer.file(
      path,
      controller: _controller,
      initialPageNumber: _page,
      params: PdfViewerParams(
        backgroundColor: _viewerBackground,
        margin: 8,
        onViewerReady: _onViewerReady,
        onPageChanged: _onPageChanged,
        onGeneralTap: _onTap,
        keyHandlerParams: const PdfViewerKeyHandlerParams(autofocus: true),
        linkHandlerParams: PdfLinkHandlerParams(
          onLinkTap: (link) {
            // Links inside the document only; the reader stays offline.
            if (link.dest != null) _controller.goToDest(link.dest);
          },
        ),
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            _buildMessage(context.l10n.readerOpenError('$error')),
      ),
    );
    final filter = _pageFilter;
    return SafeArea(
      child: filter == null
          ? viewer
          : ColorFiltered(colorFilter: filter, child: viewer),
    );
  }

  Widget _buildTopBar(Book book) {
    final l10n = context.l10n;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      left: 0,
      right: 0,
      top: _showControls ? 0 : -120,
      child: Material(
        color: _theme.bar,
        elevation: 4,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.back,
                  icon: Icon(Icons.arrow_back, color: _theme.text),
                  onPressed: _close,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _theme.text, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_outline.isNotEmpty)
                  IconButton(
                    tooltip: l10n.readerContents,
                    icon: Icon(Icons.toc, color: _theme.text),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ReaderDarkModeButton(
                  theme: _theme,
                  onChanged: _setThemeChoice,
                ),
                IconButton(
                  tooltip: l10n.readerSettings,
                  icon: Icon(Icons.tune, color: _theme.text),
                  onPressed: _openSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final l10n = context.l10n;
    final count = _pageCount;
    final page = count == 0 ? _page : _page.clamp(1, count);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      left: 0,
      right: 0,
      bottom: _showControls ? 0 : -160,
      child: Material(
        color: _theme.bar,
        elevation: 4,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 1)
                  Slider(
                    value: page.toDouble(),
                    min: 1,
                    max: count.toDouble(),
                    divisions: count - 1,
                    label: '$page',
                    onChanged: (v) => setState(() => _page = v.round()),
                    onChangeEnd: (v) => _goToPage(v.round()),
                  ),
                Row(
                  children: [
                    IconButton(
                      tooltip: l10n.readerPreviousPage,
                      icon: Icon(Icons.chevron_left, color: _theme.text),
                      onPressed: page > 1 ? () => _goToPage(page - 1) : null,
                    ),
                    Expanded(
                      child: Text(
                        count == 0 ? '' : l10n.readerPageOf(page, count),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _theme.text),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.readerNextPage,
                      icon: Icon(Icons.chevron_right, color: _theme.text),
                      onPressed:
                          page < count ? () => _goToPage(page + 1) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutline(Book book) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      style: TextStyle(
                          color: _theme.text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(book.author, style: TextStyle(color: _theme.text)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _outline.length,
                itemBuilder: (context, index) {
                  final entry = _outline[index];
                  return ListTile(
                    dense: entry.depth > 0,
                    contentPadding: EdgeInsets.only(
                        left: 16.0 + 16 * entry.depth, right: 16),
                    enabled: entry.dest != null,
                    title: Text(entry.title,
                        style: TextStyle(color: _theme.text)),
                    trailing: entry.dest == null
                        ? null
                        : Text('${entry.dest!.pageNumber}',
                            style: TextStyle(color: _theme.text)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _controller.goToDest(entry.dest);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
