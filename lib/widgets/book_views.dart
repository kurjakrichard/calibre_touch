import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'library_rebuild_dialog.dart';
import 'widgets.dart';


// ---------------------------------------------------------------------------
// View switching
// ---------------------------------------------------------------------------

/// Shows the library in the view picked with [BookViewSubmenu].
class BookViewBody extends ConsumerWidget {
  const BookViewBody({super.key, this.count = 1});

  /// Only used by the cover grid (tablet/desktop make tiles bigger).
  final double count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(booksProvider);
    if (state.books.isEmpty) {
      if (!state.loaded) {
        return const Center(child: CircularProgressIndicator());
      }
      return LibraryEmptyView(state: state);
    }
    return switch (ref.watch(bookViewProvider)) {
      BookView.grid => GridList(count: count),
      BookView.list => const BookList(),
      BookView.table => const TableView(),
    };
  }
}

/// Shown instead of the books when the library is empty or could not be
/// opened: the library folder, the reason, and a way to fix it.
class LibraryEmptyView extends ConsumerStatefulWidget {
  const LibraryEmptyView({super.key, required this.state});

  final BookState state;

  @override
  ConsumerState<LibraryEmptyView> createState() => _LibraryEmptyViewState();
}

class _LibraryEmptyViewState extends ConsumerState<LibraryEmptyView> {
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The user may grant "All files access" in the system settings and come
    // back: load the library again when the app is resumed.
    // Only for missing storage access: on desktop "resume" fires on every
    // window focus, and reloading a broken library each time floods errors.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (widget.state.error?.needsStoragePermission ?? false) {
        ref.read(booksProvider.notifier).getBooks();
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _grantAccess() async {
    setState(() => _busy = true);
    final access =
        await ref.read(booksProvider.notifier).grantAccessAndReload();
    if (!mounted) return;
    setState(() => _busy = false);
    if (access == StorageAccess.permanentlyDenied) {
      await StoragePermission.openSettings();
    }
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    await ref.read(booksProvider.notifier).getBooks();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = widget.state.error;
    final root = widget.state.libraryRoot;
    final theme = Theme.of(context);

    final String message;
    if (error == null) {
      message = l10n.libraryEmpty;
    } else if (error.needsStoragePermission) {
      message = l10n.libraryNeedsStorage;
    } else if (error.damagedDatabase) {
      message = l10n.libraryDamaged;
    } else {
      message = l10n.libraryLoadError(error.message);
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                error == null ? Icons.menu_book_outlined : Icons.folder_off,
                size: 64,
                color: error == null
                    ? theme.disabledColor
                    : theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              if (root != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  l10n.libraryLocation(root),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (error?.needsStoragePermission ?? false)
                    FilledButton.icon(
                      onPressed: _busy ? null : _grantAccess,
                      icon: const Icon(Icons.lock_open),
                      label: Text(l10n.grantAccess),
                    )
                  else if (error?.damagedDatabase ?? false) ...[
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => LibraryRebuildDialog.offer(context, ref),
                      icon: const Icon(Icons.build_outlined),
                      label: Text(l10n.rebuildDatabase),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _retry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ] else if (error != null)
                    FilledButton.icon(
                      onPressed: _busy ? null : _retry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => context.pushNamed(Routes.settings.name),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.settings),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Translated name of a [BookView].
String bookViewLabel(AppLocalizations l10n, BookView view) {
  switch (view) {
    case BookView.grid:
      return l10n.viewCovers;
    case BookView.list:
      return l10n.viewList;
    case BookView.table:
      return l10n.viewTable;
  }
}

/// "Change view" submenu of the home page menu ([HomeMenuButton]): picks
/// the view the library is shown in. Its icon shows the current view.
class BookViewSubmenu extends ConsumerWidget {
  const BookViewSubmenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(bookViewProvider);
    // Read the notifier now: MenuItemButton calls onPressed only after the
    // menu has closed, when this widget (and its ref) is already disposed.
    final viewNotifier = ref.read(bookViewProvider.notifier);
    final l10n = context.l10n;
    return SubmenuButton(
      leadingIcon: Icon(current.icon),
      menuChildren: [
        for (final view in BookView.values)
          MenuItemButton(
            leadingIcon: Icon(view.icon),
            trailingIcon: view == current ? const Icon(Icons.check) : null,
            onPressed: () => viewNotifier.setView(view),
            child: Text(bookViewLabel(l10n, view)),
          ),
      ],
      child: Text(l10n.changeView),
    );
  }
}

// ---------------------------------------------------------------------------
// Book list: list with cover, author and title
// ---------------------------------------------------------------------------

class BookList extends ConsumerWidget {
  const BookList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).visibleBooks;
    final selectedId = ref.watch(selectedBookProvider.select((b) => b?.id));

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      itemCount: books.length,
      itemExtent: 110,
      itemBuilder: (context, index) {
        final book = books[index];
        return Card(
          elevation: 5,
          clipBehavior: Clip.antiAlias,
          color: book.id == selectedId
              ? (isDark ? darkSelectedBookColor : selectedBookColor)
              : (isDark ? darkListBackground : panelColor),
          child: InkWell(
            highlightColor: isDark ? darkBookHighlightColor : bookHighlightColor,
            splashColor: isDark ? darkBookSplashColor : bookSplashColor,
            onTap: () => BookActions.select(context, ref, book),
            onDoubleTap: () => BookActions.showMenu(context, ref, book),
            onLongPress: () => BookActions.showMenu(context, ref, book),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  height: double.infinity,
                  child: BookCover(book: book),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          book.author,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          book.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Table 
// ---------------------------------------------------------------------------

class TableView extends StatelessWidget {
  const TableView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BookTable(columns: [
      BookColumn(l10n.title, 240, (b) => b.title),
      BookColumn(l10n.author, 180, (b) => b.author),
      BookColumn(l10n.series, 200, (b) => b.seriesLabel,
          compare: BookColumn.compareSeries),
      BookColumn(l10n.publisher, 160, (b) => b.publisher),
      BookColumn(l10n.tags, 200, (b) => b.tags),
      BookColumn(l10n.published, 110, (b) => BookColumn.formatPubdate(b.pubdate),
          compare: (a, b) => a.pubdate.compareTo(b.pubdate)),
      BookColumn(l10n.languages, 90, (b) => b.languages),
      BookColumn(l10n.identifiers, 220, (b) => b.identifiers),
      BookColumn(l10n.format, 80, (b) => b.format.toUpperCase()),
      BookColumn(l10n.rating, 90, (b) => BookColumn.formatRating(b.rating),
          compare: (a, b) => a.rating.compareTo(b.rating)),
      BookColumn(l10n.pages, 70, (b) => b.pages > 0 ? '${b.pages}' : '',
          compare: (a, b) => a.pages.compareTo(b.pages)),
      BookColumn(l10n.price, 80, (b) => b.price),
      BookColumn(l10n.lastModified, 130,
          (b) => BookColumn.formatDate(b.last_modified),
          compare: BookColumn.compareDates),
      BookColumn(l10n.path, 240, (b) => b.path),
      BookColumn(l10n.filename, 240, (b) => b.filename),
      BookColumn(l10n.id, 60, (b) => '${b.id ?? ''}',
          compare: (a, b) => (a.id ?? 0).compareTo(b.id ?? 0)),
    ]);
  }
}

/// One column of a [BookTable].
class BookColumn {
  BookColumn(this.label, this.width, this.value, {this.compare});

  final String label;

  /// Minimum width. Columns grow to fill wider screens; on narrow screens
  /// the table scrolls sideways instead.
  final double width;
  final String Function(Book book) value;

  /// Sort order; defaults to comparing [value] case-insensitively.
  final int Function(Book a, Book b)? compare;

  int sort(Book a, Book b) =>
      compare?.call(a, b) ??
      value(a).toLowerCase().compareTo(value(b).toLowerCase());

  /// last_modified is either a Calibre timestamp
  /// ('2024-01-31 10:00:00+00:00') or a yMMMd string written by this app.
  static DateTime? parseDate(String s) {
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed.toLocal();
    try {
      return DateFormat.yMMMd().parse(s);
    } catch (_) {
      return null;
    }
  }

  static String formatDate(String s) {
    final date = parseDate(s);
    return date == null ? s : DateFormat.yMMMd().format(date);
  }

  /// books.pubdate (Calibre timestamp, '' = none) as a local date.
  static String formatPubdate(String s) {
    if (s.isEmpty) return '';
    final date = DateTime.tryParse(s);
    return date == null ? '' : DateFormat.yMMMd().format(date.toLocal());
  }

  static int compareDates(Book a, Book b) {
    final da = parseDate(a.last_modified);
    final db = parseDate(b.last_modified);
    if (da == null && db == null) return 0;
    if (da == null) return -1;
    if (db == null) return 1;
    return da.compareTo(db);
  }

  /// By series name, then by number inside the series; books without a
  /// series come first.
  static int compareSeries(Book a, Book b) {
    final byName = a.series.toLowerCase().compareTo(b.series.toLowerCase());
    return byName != 0 ? byName : a.series_index.compareTo(b.series_index);
  }

  /// Calibre stores ratings as 0-10 (half stars); show 0-5 stars.
  static String formatRating(double rating) {
    final stars = (rating / 2).round().clamp(0, 5);
    return stars == 0 ? '' : '★' * stars;
  }
}

/// Sortable table of the visible books. Only the rows on screen are built,
/// so it stays fast with large libraries. Tap a header to sort.
///
/// Scrolling sideways (when the columns don't fit): Shift + mouse wheel,
/// mouse wheel over the header, touchpad, the always visible horizontal
/// scrollbar (desktop), or Left/Right arrows after clicking the table.
/// Up/Down, PgUp/PgDn, Home/End scroll vertically.
class BookTable extends ConsumerStatefulWidget {
  const BookTable({super.key, required this.columns});

  final List<BookColumn> columns;

  @override
  ConsumerState<BookTable> createState() => _BookTableState();
}

class _BookTableState extends ConsumerState<BookTable> {
  static const double _rowHeight = 44;

  /// Left/Right arrow scroll step in pixels.
  static const double _keyStep = 100;

  final ScrollController _hController = ScrollController();
  final ScrollController _vController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'BookTable');

  bool get _isDesktop => switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.macOS =>
          true,
        _ => false,
      };

  @override
  void dispose() {
    _hController.dispose();
    _vController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollBy(ScrollController controller, double delta) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) position.jumpTo(target);
  }

  void _scrollTo(ScrollController controller, {required bool end}) {
    if (!controller.hasClients) return;
    final position = controller.position;
    position.jumpTo(end ? position.maxScrollExtent : position.minScrollExtent);
  }

  /// Keyboard scrolling (desktop). The table gets the focus when clicked.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final page = _vController.hasClients
        ? (_vController.position.viewportDimension - _rowHeight)
            .clamp(_rowHeight, double.infinity)
        : _rowHeight;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _scrollBy(_hController, -_keyStep);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _scrollBy(_hController, _keyStep);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _scrollBy(_vController, -_rowHeight);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _scrollBy(_vController, _rowHeight);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _scrollBy(_vController, -page);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _scrollBy(_vController, page);
    } else if (key == LogicalKeyboardKey.home) {
      _scrollTo(_vController, end: false);
    } else if (key == LogicalKeyboardKey.end) {
      _scrollTo(_vController, end: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Mouse wheel over the header scrolls sideways (the header has nothing
  /// to scroll vertically). Registered before the horizontal scroll view's
  /// own handler, so the wheel's vertical delta is used.
  void _onHeaderPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_hController.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      _scrollBy(_hController, (e as PointerScrollEvent).scrollDelta.dy != 0
          ? e.scrollDelta.dy
          : e.scrollDelta.dx);
    });
  }

  int? _sortColumn;
  bool _ascending = true;

  /// Last sort result, reused while the books and the sort don't change
  /// (sorting thousands of books on every rebuild - e.g. selecting a row -
  /// is noticeable, especially by date).
  List<Book>? _sortedSource;
  int? _sortedColumn;
  bool? _sortedAscending;
  List<Book>? _sorted;

  List<Book> _sortedBooks(List<Book> books, List<BookColumn> columns) {
    final sortColumn = _sortColumn;
    if (sortColumn == null) return books;
    if (_sorted != null &&
        identical(_sortedSource, books) &&
        _sortedColumn == sortColumn &&
        _sortedAscending == _ascending) {
      return _sorted!;
    }
    final column = columns[sortColumn];
    final ascending = _ascending;
    _sortedSource = books;
    _sortedColumn = sortColumn;
    _sortedAscending = ascending;
    return _sorted = [...books]
      ..sort((a, b) => ascending ? column.sort(a, b) : column.sort(b, a));
  }

  void _onHeaderTap(int index) {
    setState(() {
      if (_sortColumn == index) {
        _ascending = !_ascending;
      } else {
        _sortColumn = index;
        _ascending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final columns = widget.columns;
    final selectedId = ref.watch(selectedBookProvider.select((b) => b?.id));
    final books =
        _sortedBooks(ref.watch(booksProvider).visibleBooks, columns);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerStyle = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.bold, color: isDark ? darkFontColor : buttonColor);
    final stripe = isDark ? darkListStripeColor : listStripeColor;

    return LayoutBuilder(builder: (context, constraints) {
      final minWidth = columns.fold<double>(0, (sum, c) => sum + c.width);
      final scale =
          constraints.maxWidth > minWidth ? constraints.maxWidth / minWidth : 1.0;
      final widths = [for (final c in columns) c.width * scale];
      final tableWidth = minWidth * scale;

      Widget cell(String text, double width, {TextStyle? style, Widget? icon}) {
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(text,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (icon != null) icon,
              ],
            ),
          ),
        );
      }

      final header = Listener(
        onPointerSignal: _onHeaderPointerSignal,
        child: Material(
          color: isDark ? darkListBackground : panelColor,
          child: SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                for (var i = 0; i < columns.length; i++)
                  InkWell(
                    onTap: () => _onHeaderTap(i),
                    child: SizedBox(
                      height: _rowHeight,
                      child: cell(
                        columns[i].label,
                        widths[i],
                        style: headerStyle,
                        icon: _sortColumn == i
                            ? Icon(
                                _ascending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 16,
                                color: headerStyle?.color,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      final body = ListView.builder(
        controller: _vController,
        itemCount: books.length,
        itemExtent: _rowHeight,
        itemBuilder: (context, index) {
          final book = books[index];
          final selected = book.id == selectedId;
          return Material(
            color: selected
                ? (isDark ? darkSelectedBookColor : selectedBookColor)
                : (index.isOdd ? stripe : transparentColor),
            child: InkWell(
              highlightColor: isDark ? darkBookHighlightColor : bookHighlightColor,
              splashColor: isDark ? darkBookSplashColor : bookSplashColor,
              onTap: () => BookActions.select(context, ref, book),
              onDoubleTap: () => BookActions.showMenu(context, ref, book),
              onLongPress: () => BookActions.showMenu(context, ref, book),
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++)
                    cell(columns[i].value(book), widths[i]),
                ],
              ),
            ),
          );
        },
      );

      final table = SizedBox(
        width: tableWidth,
        height: constraints.maxHeight,
        child: Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      );

      final scrollsSideways = minWidth > constraints.maxWidth;

      // The vertical list's scrollbar would sit at the right edge of the
      // (wide) table, off screen. Both scrollbars are drawn here instead,
      // at the edges of the visible area; the automatic ones are turned off.
      Widget content = scrollsSideways
          ? Scrollbar(
              controller: _hController,
              thumbVisibility: _isDesktop,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _hController,
                scrollDirection: Axis.horizontal,
                child: table,
              ),
            )
          : table;

      content = Scrollbar(
        controller: _vController,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: content,
        ),
      );

      if (!_isDesktop) return content;
      return Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (_) {
            if (!_focusNode.hasFocus) _focusNode.requestFocus();
          },
          child: content,
        ),
      );
    });
  }
}
