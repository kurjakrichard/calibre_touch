import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'book_actions.dart';
import 'book_cover.dart';
import 'grid_list.dart';

// ---------------------------------------------------------------------------
// View switching
// ---------------------------------------------------------------------------

/// Shows the library in the view picked with [BookViewMenuButton].
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
    switch (ref.watch(bookViewProvider)) {
      case BookView.grid:
        return GridList(count: count);
      case BookView.flutibreList:
        return const FlutibreListView();
      case BookView.proTable:
        return const ProTableView();
    }
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
    _lifecycle = AppLifecycleListener(onResume: () {
      if (widget.state.error != null) {
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
                  else if (error != null)
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
    case BookView.flutibreList:
      return l10n.viewList;
    case BookView.proTable:
      return l10n.viewTable;
  }
}

/// App bar button that switches between the views. Its icon shows the
/// current view.
class BookViewMenuButton extends ConsumerWidget {
  const BookViewMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(bookViewProvider);
    final l10n = context.l10n;
    return PopupMenuButton<BookView>(
      tooltip: l10n.changeView,
      icon: Icon(current.icon),
      initialValue: current,
      onSelected: (view) => ref.read(bookViewProvider.notifier).setView(view),
      itemBuilder: (context) => [
        for (final view in BookView.values)
          PopupMenuItem<BookView>(
            value: view,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(view.icon),
              title: Text(bookViewLabel(l10n, view)),
              trailing: view == current ? const Icon(Icons.check) : null,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Flutibre: list with cover, author and title
// ---------------------------------------------------------------------------

class FlutibreListView extends ConsumerWidget {
  const FlutibreListView({super.key});

  static const Color _rowColor = Color.fromRGBO(98, 163, 191, 0.3);
  static const Color _selectedColor = Color.fromRGBO(98, 163, 191, 0.7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).visibleBooks;
    final selectedId = ref.watch(selectedBookProvider.select((b) => b?.id));

    return ListView.builder(
      itemCount: books.length,
      itemExtent: 110,
      itemBuilder: (context, index) {
        final book = books[index];
        return Card(
          elevation: 5,
          clipBehavior: Clip.antiAlias,
          color: book.id == selectedId ? _selectedColor : _rowColor,
          child: InkWell(
            highlightColor: const Color.fromARGB(255, 47, 119, 177),
            splashColor: Colors.green,
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
// Table (Flutibre Pro: every field)
// ---------------------------------------------------------------------------

class ProTableView extends StatelessWidget {
  const ProTableView({super.key});

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
class BookTable extends ConsumerStatefulWidget {
  const BookTable({super.key, required this.columns});

  final List<BookColumn> columns;

  @override
  ConsumerState<BookTable> createState() => _BookTableState();
}

class _BookTableState extends ConsumerState<BookTable> {
  static const double _rowHeight = 44;
  static const Color _selectedColor = Color.fromRGBO(98, 163, 191, 0.7);

  int? _sortColumn;
  bool _ascending = true;

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
    var books = ref.watch(booksProvider).visibleBooks;
    final sortColumn = _sortColumn;
    if (sortColumn != null) {
      final column = columns[sortColumn];
      books = [...books]..sort((a, b) =>
          _ascending ? column.sort(a, b) : column.sort(b, a));
    }

    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.bold, color: buttoncolor);
    final stripe = theme.colorScheme.onSurface.withValues(alpha: 0.04);

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

      final header = Material(
        color: secondary,
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
                              color: buttoncolor,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

      final body = ListView.builder(
        itemCount: books.length,
        itemExtent: _rowHeight,
        itemBuilder: (context, index) {
          final book = books[index];
          final selected = book.id == selectedId;
          return Material(
            color: selected
                ? _selectedColor
                : (index.isOdd ? stripe : Colors.transparent),
            child: InkWell(
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

      return minWidth > constraints.maxWidth
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            )
          : table;
    });
  }
}
