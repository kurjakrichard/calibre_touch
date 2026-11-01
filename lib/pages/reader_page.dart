import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import '../utils/book_documents.dart';
import '../utils/mobi_document.dart';
import '../utils/utils.dart';

/// Colour schemes of the reader. Independent of the app's own light/dark
/// theme, like in a standalone e-book reader.
enum ReaderTheme {
  light(readerLightBackground, readerLightText, readerLightBar),
  sepia(readerSepiaBackground, readerSepiaText, readerSepiaBar),
  dark(readerDarkBackground, readerDarkText, readerDarkBar);

  const ReaderTheme(this.background, this.text, this.bar);

  final Color background;
  final Color text;
  final Color bar;

  Brightness get brightness =>
      this == ReaderTheme.dark ? Brightness.dark : Brightness.light;

  /// SharedPreferences key shared by the EPUB and PDF readers.
  static const prefKey = 'readerTheme';
  static const _autoValue = 'auto';

  /// The saved choice: a fixed theme, or null for "Auto" (follow the app's
  /// light/dark theme). Nothing saved yet = Auto.
  static ReaderTheme? loadChoice(SharedPreferences prefs) {
    final saved = prefs.getString(prefKey);
    for (final theme in ReaderTheme.values) {
      if (theme.name == saved) return theme;
    }
    return null;
  }

  static void saveChoice(SharedPreferences prefs, ReaderTheme? choice) =>
      prefs.setString(prefKey, choice?.name ?? _autoValue);

  /// The theme to show for [choice]; Auto follows the app's theme mode
  /// ([modeProvider] value).
  static ReaderTheme resolve(ReaderTheme? choice, String appMode) =>
      choice ?? (appMode == 'dark' ? ReaderTheme.dark : ReaderTheme.light);

  static String label(AppLocalizations l10n, ReaderTheme? choice) {
    switch (choice) {
      case null:
        return l10n.readerThemeAuto;
      case ReaderTheme.light:
        return l10n.readerThemeLight;
      case ReaderTheme.sepia:
        return l10n.readerThemeSepia;
      case ReaderTheme.dark:
        return l10n.readerThemeDark;
    }
  }
}

/// Auto / Light / Sepia / Dark chips for the readers' settings sheets.
class ReaderThemeChips extends StatelessWidget {
  const ReaderThemeChips({
    super.key,
    required this.choice,
    required this.onChanged,
  });

  final ReaderTheme? choice;
  final ValueChanged<ReaderTheme?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final theme in <ReaderTheme?>[null, ...ReaderTheme.values])
          ChoiceChip(
            avatar: theme == null ? const Icon(Icons.brightness_auto) : null,
            label: Text(ReaderTheme.label(l10n, theme)),
            selected: choice == theme,
            onSelected: (_) => onChanged(theme),
          ),
      ],
    );
  }
}

/// Top bar button that switches the reader between dark and light in one
/// tap (a fixed choice; Auto can be picked again in the settings sheet).
class ReaderDarkModeButton extends StatelessWidget {
  const ReaderDarkModeButton({
    super.key,
    required this.theme,
    required this.onChanged,
  });

  /// The theme being shown.
  final ReaderTheme theme;
  final ValueChanged<ReaderTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = theme == ReaderTheme.dark;
    return IconButton(
      tooltip: isDark ? l10n.readerLightMode : l10n.readerDarkMode,
      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
          color: theme.text),
      onPressed: () =>
          onChanged(isDark ? ReaderTheme.light : ReaderTheme.dark),
    );
  }
}

/// Full-screen EPUB reader for the selected book.
///
/// It looks and behaves like a standalone e-book reader app: its own page
/// colours (light / sepia / dark), no library app bar or drawer, system bars
/// hidden on phones, and controls that appear only when the page is tapped.
/// The book is shown one chapter (spine section) at a time. Swipe left/right
/// turns a page (one screenful); past the end of a chapter the next one
/// starts, before the start the previous one is shown from its end, so the
/// book reads continuously. Scrolling works the same way: pulling on past
/// the end of a chapter and letting go opens the next one, pulling past the
/// start opens the previous one at its end. Text is justified (can be turned
/// off). Reading position and settings are remembered.
///
/// Desktop keys: Esc closes, Right/PageDown/Space = next page, Left/PageUp =
/// previous page, Up/Down scroll a little (and at the end / start of a
/// chapter go on to the next / previous one, like the mouse wheel).
class ReaderPage extends ConsumerStatefulWidget {
  static Page<void> pageBuilder(BuildContext context, GoRouterState state) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        // extra = the format to open (e.g. 'PDF'), null = the book's default.
        child: ReaderPage(format: state.extra as String?),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  const ReaderPage({super.key, this.format});

  /// Which of the selected book's formats to open; null = [Book.format].
  final String? format;

  /// Whether the built-in reader can open [book].
  /// EPUB, MOBI/AZW3, TXT, DOCX, ODT, RTF ([BookDocuments]).
  static bool canRead(Book book) => BookDocuments.canRead(book.format);

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  static const _fontSizeKey = 'readerFontSize';
  static const _lineHeightKey = 'readerLineHeight';
  static const _justifyKey = 'readerJustify';
  static const double _maxTextWidth = 760;

  /// How far (logical px) to pull past the end / start of a chapter before
  /// letting go moves to the next / previous chapter.
  static const double _pullThreshold = 64;

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

  /// How far the current drag has pulled past the end (positive) or the
  /// start (negative) of the chapter. Also drives the arrow hint.
  final _pull = ValueNotifier<double>(0);

  bool _showControls = false;
  double _fontSize = 18;
  double _lineHeight = 1.5;
  bool _justify = true;
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

    final prefs = _prefs = ref.read(sharedPreferencesProvider);
    _book = ref.read(selectedBookProvider)?.withFormat(widget.format);
    // Per library + book, so the same book in another library has its own.
    _positionKey = 'readerPosition:${ref.read(pathProvider)}|'
        '${_book?.path}/${_book?.filename}';
    _fontSize = prefs.getDouble(_fontSizeKey) ?? _fontSize;
    _lineHeight = prefs.getDouble(_lineHeightKey) ?? _lineHeight;
    _justify = prefs.getBool(_justifyKey) ?? _justify;
    _themeChoice = ReaderTheme.loadChoice(prefs);
    _appMode = ref.read(modeProvider);

    final book = _book;
    // Remember it for the drawer's "Continue reading" button (after this
    // frame: providers can't be modified while the widget tree builds).
    if (book != null && ReaderPage.canRead(book)) {
      Future.microtask(() {
        if (mounted) ref.read(recentBooksProvider.notifier).add(book);
      });
    }
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
    _pull.dispose();
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
      final parser = BookDocuments.parserFor(book.format)!;
      final document = await compute(parser, bytes);
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

  /// Scrolling on past a chapter's end (or start) with the finger moves to
  /// the next (or previous) chapter when the finger is lifted. Flings that
  /// merely run into the edge don't (no drag details then).
  bool _onScrollNotification(ScrollNotification n) {
    _onScroll();
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _pull.value = 0;
    } else if (n is OverscrollNotification) {
      // Clamping physics (Android, desktop): the list is at its edge and
      // the finger keeps going.
      if (n.dragDetails != null) _pull.value += n.overscroll;
    } else if (n is ScrollUpdateNotification) {
      if (n.dragDetails != null) {
        final m = n.metrics;
        if (m.pixels > m.maxScrollExtent) {
          // Bouncing physics (iOS): the list itself goes past its edge.
          _pull.value = m.pixels - m.maxScrollExtent;
        } else if (m.pixels < m.minScrollExtent) {
          _pull.value = m.pixels - m.minScrollExtent;
        } else {
          // Back inside the text: the pull is cancelled.
          _pull.value = 0;
        }
      }
    } else if (n is ScrollEndNotification) {
      final pull = _pull.value;
      _pull.value = 0;
      if (pull >= _pullThreshold) {
        _goToSection(_section + 1);
      } else if (pull <= -_pullThreshold) {
        _goToSection(_section - 1, atEnd: true);
      }
    }
    return false;
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

  /// Opens chapter [index] at its start, or at its end if [atEnd] (when
  /// paging backwards from the start of the following chapter).
  void _goToSection(int index, {bool atEnd = false}) {
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
    if (atEnd) _jumpToEnd();
    _savePosition();
  }

  /// Jumps to the end of the chapter. Big chapters are built in the
  /// background (empty, length 0, for a while) and then laid out lazily, so
  /// the length keeps growing for some frames: keep jumping to the end until
  /// it has a length and stays the same for a few frames (at most ~3 s).
  /// Stops if the chapter changes or the reader scrolls away meanwhile.
  void _jumpToEnd() {
    final controller = _scroll;
    var frames = 0;
    var stable = 0;
    double? last;
    void step(Duration _) {
      if (!mounted || !identical(controller, _scroll) || ++frames > 180) {
        return;
      }
      if (controller.hasClients) {
        final position = controller.position;
        final max = position.maxScrollExtent;
        final jumped = last;
        if (jumped != null &&
            (position.pixels - jumped).abs() > 1 &&
            (position.pixels - max).abs() > 1) {
          return; // the reader scrolled meanwhile
        }
        if (max > 0 && max == jumped) {
          if (++stable >= 5) return;
        } else {
          stable = 0;
        }
        controller.jumpTo(max);
        last = max;
      }
      WidgetsBinding.instance.addPostFrameCallback(step);
      WidgetsBinding.instance.scheduleFrame();
    }

    WidgetsBinding.instance.addPostFrameCallback(step);
  }

  /// How far one page turn scrolls: the visible height minus one line, so
  /// a line cut at the bottom edge is shown again whole at the top.
  double get _pageStep {
    if (!_scroll.hasClients) return 400;
    final step =
        _scroll.position.viewportDimension - _fontSize * _lineHeight;
    return step < 100 ? 100 : step;
  }

  /// Next screenful; at the end of a chapter, the start of the next one.
  void _nextPage() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 1) {
      _goToSection(_section + 1);
      return;
    }
    _scroll.jumpTo(
        (position.pixels + _pageStep).clamp(0.0, position.maxScrollExtent));
    _onScroll();
  }

  /// Previous screenful; at the start of a chapter, the end of the
  /// previous one.
  void _previousPage() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= 1) {
      _goToSection(_section - 1, atEnd: true);
      return;
    }
    _scroll.jumpTo(
        (position.pixels - _pageStep).clamp(0.0, position.maxScrollExtent));
    _onScroll();
  }

  /// Down key / wheel: a little further; already at the end of the chapter
  /// → the next chapter from its start.
  void _lineDown() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 1) {
      _goToSection(_section + 1);
    } else {
      _scrollBy(60);
    }
  }

  /// Up key / wheel: a little back; already at the start of the chapter →
  /// the previous chapter at its end.
  void _lineUp() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels <= 1) {
      _goToSection(_section - 1, atEnd: true);
    } else {
      _scrollBy(-60);
    }
  }

  /// Mouse wheel against the end / start of a chapter (the list itself
  /// can't go further) moves to the next / previous chapter. Runs before
  /// the list scrolls, so the wheel first has to reach the edge.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    final dy = event.scrollDelta.dy;
    if (dy > 0 && position.pixels >= position.maxScrollExtent - 1) {
      _goToSection(_section + 1);
    } else if (dy < 0 && position.pixels <= 1) {
      _goToSection(_section - 1, atEnd: true);
    }
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
                            max: 50,
                            divisions: 28,
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary:
                          Icon(Icons.format_align_justify, color: _theme.text),
                      title: Text(l10n.readerJustify, style: labelStyle),
                      value: _justify,
                      onChanged: (v) {
                        update(() => _justify = v);
                        _prefs.setBool(_justifyKey, v);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.readerTheme, style: labelStyle),
                    const SizedBox(height: 8),
                    ReaderThemeChips(
                      choice: _themeChoice,
                      onChanged: (choice) {
                        _setThemeChoice(choice);
                        setSheetState(() {});
                      },
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

  // ---- UI ----

  ThemeData _themeData(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      brightness: _theme.brightness,
      scaffoldBackgroundColor: _theme.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: buttonColor,
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
    // Auto page colour follows the app theme, also if it changes meanwhile.
    _appMode = ref.watch(modeProvider);
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
      body = _buildMessage(_error is MobiDrmException
          ? l10n.readerDrmProtected
          : l10n.readerOpenError('$_error'));
    } else {
      body = Stack(
        children: [
          Positioned.fill(child: _buildText(document)),
          Positioned.fill(child: _buildPullHint(document)),
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
          const SingleActivator(LogicalKeyboardKey.arrowRight): _nextPage,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _previousPage,
          const SingleActivator(LogicalKeyboardKey.arrowDown): _lineDown,
          const SingleActivator(LogicalKeyboardKey.arrowUp): _lineUp,
          const SingleActivator(LogicalKeyboardKey.pageDown): _nextPage,
          const SingleActivator(LogicalKeyboardKey.space): _nextPage,
          const SingleActivator(LogicalKeyboardKey.pageUp): _previousPage,
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
    final html = section.html;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) _nextPage();
        if (velocity > 300) _previousPage();
      },
      // Only reached when the chapter is too short to scroll (otherwise
      // the list takes the vertical drag): swipe up/down = next/previous.
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) _goToSection(_section + 1);
        if (velocity > 300) _goToSection(_section - 1, atEnd: true);
      },
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxTextWidth),
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
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
                rebuildTriggers: [_theme, _fontSize, _lineHeight, _justify],
                customStylesBuilder: _styles,
                customWidgetBuilder: (element) =>
                    _customWidget(element, section, document),
                onTapUrl: (url) => _onLink(url, section),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  /// Arrow at the bottom (or top) edge that fades in while pulling past the
  /// end (or start) of a chapter; fully visible = letting go turns.
  Widget _buildPullHint(EpubDocument document) => IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: _pull,
          builder: (context, pull, _) {
            final next = pull > 0;
            final hasTarget = next
                ? _section < document.sections.length - 1
                : _section > 0;
            if (pull == 0 || !hasTarget) return const SizedBox.shrink();
            final progress = (pull.abs() / _pullThreshold).clamp(0.0, 1.0);
            return SafeArea(
              child: Align(
                alignment:
                    next ? Alignment.bottomCenter : Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Opacity(
                    opacity: progress,
                    child: Icon(
                      next
                          ? Icons.keyboard_double_arrow_down
                          : Icons.keyboard_double_arrow_up,
                      size: 32,
                      color: _theme.text,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  /// Text blocks justified (if turned on) unless the book aligns them
  /// itself, e.g. a centred line.
  static const _justifiedTags = {
    'p', 'div', 'li', 'blockquote', 'dd', 'dt', 'section', 'article',
  };

  /// Keeps the book's colours from fighting the reader theme, and justifies
  /// paragraphs.
  Map<String, String>? _styles(dom.Element element) {
    final style = element.attributes['style'] ?? '';
    final result = <String, String>{};
    if (style.contains('color')) {
      final rgb = (_theme.text.toARGB32() & 0xFFFFFF).toRadixString(16);
      result['color'] = '#${rgb.padLeft(6, '0')}';
      result['background-color'] = 'transparent';
    }
    if (_justify &&
        _justifiedTags.contains(element.localName) &&
        !style.contains('text-align') &&
        element.attributes['align'] == null) {
      result['text-align'] = 'justify';
    }
    return result.isEmpty ? null : result;
  }

  /// Images come from inside the EPUB.
  Widget? _customWidget(
      dom.Element element, EpubSection section, EpubDocument document) {
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
                ReaderDarkModeButton(
                  theme: _theme,
                  onChanged: _setThemeChoice,
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
                                color: _theme.text.withValues(alpha: readerSecondaryTextOpacity),
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
