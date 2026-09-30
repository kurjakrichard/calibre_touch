import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/epub_document.dart';
import '../utils/utils.dart';

/// Colour schemes of the reader. Independent of the app's own light/dark
/// theme, like in a standalone e-book reader.
enum ReaderTheme {
  light(Color(0xFFFFFFFF), Color(0xFF1F1F1F), Color(0xFFF1F1F1)),
  sepia(Color(0xFFF4ECD8), Color(0xFF5B4636), Color(0xFFE8DDC4)),
  dark(Color(0xFF121212), Color(0xFFD6D6D6), Color(0xFF1E1E1E));

  const ReaderTheme(this.background, this.text, this.bar);

  final Color background;
  final Color text;
  final Color bar;

  Brightness get brightness =>
      this == ReaderTheme.dark ? Brightness.dark : Brightness.light;
}

/// Full-screen EPUB reader for the selected book.
///
/// It looks and behaves like a standalone e-book reader app: its own page
/// colours (light / sepia / dark), no library app bar or drawer, system bars
/// hidden on phones, and controls that appear only when the page is tapped.
/// The book is shown one chapter (spine section) at a time; swipe left/right
/// or use the arrows to change chapter. Reading position and settings are
/// remembered.
///
/// Desktop keys: Esc closes, Left/Right change chapter, Up/Down/PageUp/
/// PageDown/Space scroll.
class ReaderPage extends ConsumerStatefulWidget {
  static Page<void> pageBuilder(BuildContext context, GoRouterState state) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        child: const ReaderPage(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  const ReaderPage({super.key});

  /// Whether the built-in reader can open [book].
  static bool canRead(Book book) => book.format.toLowerCase() == 'epub';

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  static const _fontSizeKey = 'readerFontSize';
  static const _lineHeightKey = 'readerLineHeight';
  static const _themeKey = 'readerTheme';
  static const double _maxTextWidth = 760;
  static const String _nextChapterMarker = 'calibre-touch-next-chapter';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _focusNode = FocusNode();

  late final SharedPreferences _prefs;
  late final String _positionKey;
  Book? _book;

  EpubDocument? _document;
  Object? _error;
  bool _loading = true;

  int _section = 0;
  ScrollController _scroll = ScrollController();
  Timer? _saveTimer;

  bool _showControls = false;
  double _fontSize = 18;
  double _lineHeight = 1.5;
  ReaderTheme _theme = ReaderTheme.light;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final prefs = _prefs = ref.read(sharedPreferencesProvider);
    _book = ref.read(selectedBookProvider);
    // Per library + book, so the same book in another library has its own.
    _positionKey = 'readerPosition:${ref.read(pathProvider)}|'
        '${_book?.path}/${_book?.filename}';
    _fontSize = prefs.getDouble(_fontSizeKey) ?? _fontSize;
    _lineHeight = prefs.getDouble(_lineHeightKey) ?? _lineHeight;
    _theme = ReaderTheme.values.firstWhere(
      (t) => t.name == prefs.getString(_themeKey),
      orElse: () => ReaderTheme.light,
    );

    final book = _book;
    if (book != null && ReaderPage.canRead(book)) {
      _load(book);
    } else {
      _loading = false;
    }
    _applySystemUi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _savePosition();
    _scroll.dispose();
    _focusNode.dispose();
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

  Future<void> _load(Book book) async {
    try {
      final path = await FileService().bookFilePath(
        path: book.path,
        filename: book.filename,
        // Calibre stores the format upper-case ('EPUB'), the file extension
        // is lower-case.
        format: book.format.toLowerCase(),
        customPath: ref.read(pathProvider),
      );
      final bytes = await File(path).readAsBytes();
      // Unzipping and parsing can take a moment for big books - keep the
      // UI responsive.
      final document = await compute(EpubDocument.parse, bytes);
      if (!mounted) return;

      final saved = _prefs.getString(_positionKey)?.split(':');
      final section = int.tryParse(saved?.first ?? '') ?? 0;
      final offset = double.tryParse(saved?.last ?? '') ?? 0;
      setState(() {
        _document = document;
        _section = section.clamp(0, document.sections.length - 1);
        _loading = false;
      });
      _restoreOffset(offset);
    } catch (e) {
      debugPrint('Reader: could not open book: $e');
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  // ---- reading position ----

  void _onScroll() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 2), _savePosition);
  }

  void _savePosition() {
    if (_document == null) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    _prefs.setString(_positionKey, '$_section:${offset.toStringAsFixed(0)}');
  }

  /// Jumps to [offset] once the chapter has been laid out (big chapters
  /// are built asynchronously, so this retries for a few frames).
  void _restoreOffset(double offset, [int attempts = 30]) {
    if (offset <= 0 || attempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
        _scroll.jumpTo(offset);
      } else {
        _restoreOffset(offset, attempts - 1);
      }
    });
  }

  void _goToSection(int index) {
    final document = _document;
    if (document == null) return;
    if (index < 0 || index >= document.sections.length) return;
    if (index == _section) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    final old = _scroll;
    setState(() {
      _section = index;
      // A fresh controller per chapter: each chapter is its own list.
      _scroll = ScrollController();
    });
    // The old list is gone after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _savePosition();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.animateTo(
      (_scroll.offset + delta).clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  double get _pageHeight =>
      _scroll.hasClients ? _scroll.position.viewportDimension * 0.9 : 400;

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

  /// Index in the table of contents of the chapter being read.
  int get _currentTocIndex {
    final toc = _document?.toc ?? const <EpubTocEntry>[];
    var result = -1;
    for (var i = 0; i < toc.length; i++) {
      final section = toc[i].sectionIndex;
      if (section >= 0 && section <= _section) result = i;
    }
    return result;
  }

  /// Title of the chapter being read (from the table of contents).
  String get _chapterTitle {
    final index = _currentTocIndex;
    return index < 0 ? '' : _document!.toc[index].title;
  }

  // ---- settings ----

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _theme.bar,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          final l10n = context.l10n;
          final labelStyle = TextStyle(color: _theme.text);
          return Theme(
            data: _themeData(context),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.readerFontSize, style: labelStyle),
                    Row(
                      children: [
                        Icon(Icons.text_decrease, color: _theme.text),
                        Expanded(
                          child: Slider(
                            value: _fontSize,
                            min: 12,
                            max: 32,
                            divisions: 20,
                            label: _fontSize.round().toString(),
                            onChanged: (v) => update(() => _fontSize = v),
                            onChangeEnd: (v) =>
                                _prefs.setDouble(_fontSizeKey, v),
                          ),
                        ),
                        Icon(Icons.text_increase, color: _theme.text),
                      ],
                    ),
                    Text(l10n.readerLineSpacing, style: labelStyle),
                    Slider(
                      value: _lineHeight,
                      min: 1.0,
                      max: 2.2,
                      divisions: 12,
                      label: _lineHeight.toStringAsFixed(1),
                      onChanged: (v) => update(() => _lineHeight = v),
                      onChangeEnd: (v) =>
                          _prefs.setDouble(_lineHeightKey, v),
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.readerTheme, style: labelStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final theme in ReaderTheme.values)
                          ChoiceChip(
                            label: Text(_themeName(l10n, theme)),
                            selected: _theme == theme,
                            onSelected: (_) {
                              update(() => _theme = theme);
                              _prefs.setString(_themeKey, theme.name);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _themeName(AppLocalizations l10n, ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return l10n.readerThemeLight;
      case ReaderTheme.sepia:
        return l10n.readerThemeSepia;
      case ReaderTheme.dark:
        return l10n.readerThemeDark;
    }
  }

  // ---- UI ----

  ThemeData _themeData(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      brightness: _theme.brightness,
      scaffoldBackgroundColor: _theme.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: buttoncolor,
        brightness: _theme.brightness,
      ),
      iconTheme: IconThemeData(color: _theme.text),
      textTheme: base.textTheme.apply(
        bodyColor: _theme.text,
        displayColor: _theme.text,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: _theme.bar),
      listTileTheme: ListTileThemeData(textColor: _theme.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final book = _book;
    final document = _document;

    Widget body;
    if (book == null) {
      body = _buildMessage(l10n.noBookSelected);
    } else if (!ReaderPage.canRead(book)) {
      body = _buildMessage(l10n.readerUnsupported(book.format));
    } else if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (document == null) {
      body = _buildMessage(l10n.readerOpenError('$_error'));
    } else {
      body = Stack(
        children: [
          Positioned.fill(child: _buildText(document)),
          _buildTopBar(book, document),
          _buildBottomBar(document),
        ],
      );
    }

    return Theme(
      data: _themeData(context),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _showControls ? _toggleControls() : _close(),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _goToSection(_section + 1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _goToSection(_section - 1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _scrollBy(60),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _scrollBy(-60),
          const SingleActivator(LogicalKeyboardKey.pageDown): () =>
              _scrollBy(_pageHeight),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              _scrollBy(_pageHeight),
          const SingleActivator(LogicalKeyboardKey.pageUp): () =>
              _scrollBy(-_pageHeight),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: _theme.background,
            drawer: document == null ? null : _buildContents(book!, document),
            body: body,
          ),
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
                icon: const Icon(Icons.arrow_back),
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

  /// The text of the current chapter.
  Widget _buildText(EpubDocument document) {
    final section = document.sections[_section];
    final isLast = _section >= document.sections.length - 1;
    // A marker at the end of the chapter, rendered as a "next chapter"
    // button by customWidgetBuilder below.
    final html = isLast
        ? section.html
        : '${section.html}<div id="$_nextChapterMarker"></div>';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) _goToSection(_section + 1);
        if (velocity > 300) _goToSection(_section - 1);
      },
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxTextWidth),
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _onScroll();
                return false;
              },
              child: HtmlWidget(
                html,
                // New key per chapter: forget the previous chapter's layout.
                key: ValueKey('section-$_section'),
                renderMode: ListViewMode(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                ),
                textStyle: TextStyle(
                  fontSize: _fontSize,
                  height: _lineHeight,
                  color: _theme.text,
                ),
                rebuildTriggers: [_theme, _fontSize, _lineHeight],
                customStylesBuilder: _styles,
                customWidgetBuilder: (element) =>
                    _customWidget(element, section, document),
                onTapUrl: (url) => _onLink(url, section),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the book's colours from fighting the reader theme.
  Map<String, String>? _styles(dom.Element element) {
    final style = element.attributes['style'] ?? '';
    if (style.contains('color')) {
      final rgb = (_theme.text.toARGB32() & 0xFFFFFF).toRadixString(16);
      return {
        'color': '#${rgb.padLeft(6, '0')}',
        'background-color': 'transparent',
      };
    }
    return null;
  }

  /// Images come from inside the EPUB; the end-of-chapter marker becomes a
  /// button.
  Widget? _customWidget(
      dom.Element element, EpubSection section, EpubDocument document) {
    if (element.id == _nextChapterMarker) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: () => _goToSection(_section + 1),
            icon: const Icon(Icons.chevron_right),
            label: Text(context.l10n.readerNextChapter),
          ),
        ),
      );
    }

    String? src;
    if (element.localName == 'img') {
      src = element.attributes['src'];
    } else if (element.localName == 'svg') {
      // Covers are often <svg><image xlink:href="cover.jpg"/></svg>.
      final image = element.getElementsByTagName('image').firstOrNull;
      src = image?.attributes['xlink:href'] ?? image?.attributes['href'];
    }
    if (src == null) return null;

    final bytes = document.files[EpubDocument.resolve(section.href, src)];
    if (bytes == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  /// Links inside the book jump to the right chapter; external links are
  /// ignored (the reader stays offline and full screen).
  bool _onLink(String url, EpubSection section) {
    if (url.contains('://') || url.startsWith('mailto:')) return true;
    final document = _document;
    if (document == null) return true;
    final index = document.sectionIndexOf(EpubDocument.resolve(section.href, url));
    if (index >= 0) _goToSection(index);
    return true;
  }

  Widget _buildTopBar(Book book, EpubDocument document) {
    final l10n = context.l10n;
    final title = document.title.isNotEmpty ? document.title : book.title;
    final author = document.author.isNotEmpty ? document.author : book.author;
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
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _close,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _theme.text, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (document.toc.isNotEmpty)
                  IconButton(
                    tooltip: l10n.readerContents,
                    icon: const Icon(Icons.toc),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                IconButton(
                  tooltip: l10n.readerSettings,
                  icon: const Icon(Icons.text_fields),
                  onPressed: _openSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(EpubDocument document) {
    final l10n = context.l10n;
    final count = document.sections.length;
    final percent = count <= 1 ? 100 : (_section * 100 / (count - 1)).round();
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
                    value: _section.toDouble(),
                    min: 0,
                    max: (count - 1).toDouble(),
                    divisions: count - 1,
                    label: '$percent%',
                    onChanged: (v) => _goToSection(v.round()),
                  ),
                Row(
                  children: [
                    IconButton(
                      tooltip: l10n.readerPreviousChapter,
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _section > 0
                          ? () => _goToSection(_section - 1)
                          : null,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _theme.text),
                          ),
                          Text(
                            '${l10n.readerChapterOf(_section + 1, count)}'
                            ' · $percent%',
                            style: TextStyle(
                                color: _theme.text.withValues(alpha: 0.7),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.readerNextChapter,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _section < count - 1
                          ? () => _goToSection(_section + 1)
                          : null,
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

  Widget _buildContents(Book book, EpubDocument document) {
    final current = _currentTocIndex;
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
                  Text(
                    document.title.isNotEmpty ? document.title : book.title,
                    style: TextStyle(
                        color: _theme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    document.author.isNotEmpty ? document.author : book.author,
                    style: TextStyle(color: _theme.text),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: document.toc.length,
                itemBuilder: (context, index) {
                  final entry = document.toc[index];
                  return ListTile(
                    dense: entry.depth > 0,
                    contentPadding:
                        EdgeInsets.only(left: 16.0 + 16 * entry.depth, right: 16),
                    selected: index == current,
                    enabled: entry.sectionIndex >= 0,
                    title: Text(entry.title,
                        style: TextStyle(
                            color: _theme.text,
                            fontWeight: index == current
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _goToSection(entry.sectionIndex);
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
