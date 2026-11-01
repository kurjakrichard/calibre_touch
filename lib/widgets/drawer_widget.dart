import 'package:calibre_touch/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import 'book_actions.dart';
import 'book_cover.dart';

class DrawerWidget extends ConsumerWidget {
  const DrawerWidget({super.key});

  /// Online user manual, opened by the "Help" tile.
  static final Uri helpUrl =
      Uri.parse('https://kurjakrichard.github.io/calibre_touch_public/');

  /// Opens [helpUrl] in the system browser; snackbar if that fails.
  static Future<void> _openHelp(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = context.l10n.helpOpenFailed;
    var ok = false;
    try {
      ok = await launchUrl(helpUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Help: $e');
    }
    if (!ok) {
      messenger?.showSnackBar(SnackBar(content: Text('$failed\n$helpUrl')));
    }
  }

  /// On phones/tablets this widget is the Scaffold's slide-out drawer:
  /// close it before opening another page, otherwise it is still open when
  /// the user comes back. On desktop it is embedded in the page body (never
  /// "open"), so nothing is closed there - don't use Navigator.pop, it
  /// would pop the route.
  static void _closeDrawer(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    }
  }

  /// Long press on "Continue reading": the last [RecentBooksNotifier.max]
  /// books read (that still exist), newest first; opens the chosen one.
  static Future<void> _chooseRecentBook(
      BuildContext context, WidgetRef ref) async {
    final books = ref.read(booksProvider).books;
    final recent = ref
        .read(recentBooksProvider)
        .map((id) => books.where((b) => b.id == id).firstOrNull)
        .nonNulls
        .toList();
    if (recent.isEmpty) return;
    final book = await showDialog<Book>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.recentBooks),
        children: [
          for (final book in recent)
            ListTile(
              leading: SizedBox(
                width: 36,
                height: 52,
                child: BookCover(book: book),
              ),
              title: Text(book.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(book.author,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, book),
            ),
        ],
      ),
    );
    if (book == null || !context.mounted) return;
    _closeDrawer(context);
    BookActions.open(context, ref, book);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Last book opened in the built-in reader (this library), if it still
    // exists.
    final lastId = ref.watch(lastReadBookProvider);
    final lastBook = lastId == null
        ? null
        : ref
            .watch(booksProvider.select((s) => s.books))
            .where((b) => b.id == lastId)
            .firstOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? darkDrawerTextColor : buttonColor;
    final disabledColor =
        isDark ? darkDrawerDisabledColor : disabledButtonColor;

    return Drawer(
      child: ListView(
        children: [
          SizedBox(
            height: 72,
            child: DrawerHeader(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    Image.asset(
                      'assets/flutibre-icon.png',
                      height: 64,
                    ),
                    Expanded(
                      child: Text(
                        context.l10n.appTitle,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            height: 2,
                            overflow: TextOverflow.clip),
                      ),
                    ),
                  ],
                )),
          ),
          // Hover only (manual): a touch long press must reach the tile's
          // onLongPress, not show the tooltip.
          Tooltip(
            message: lastBook == null ? '' : context.l10n.recentBooksHint,
            triggerMode: TooltipTriggerMode.manual,
            child: ListTile(
              enabled: lastBook != null,
              leading: Icon(Icons.menu_book_outlined,
                  color: lastBook != null ? textColor : disabledColor),
              title: Text(
                context.l10n.continueReading,
                style: TextStyle(
                    color: lastBook != null ? textColor : disabledColor),
              ),
              subtitle: Text(
                lastBook?.title ?? context.l10n.noRecentBook,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: disabledColor),
              ),
              onTap: lastBook == null
                  ? null
                  : () {
                      _closeDrawer(context);
                      BookActions.open(context, ref, lastBook);
                    },
              onLongPress: lastBook == null
                  ? null
                  : () => _chooseRecentBook(context, ref),
            ),
          ),
          ListTile(
            leading: Icon(Icons.settings_outlined, color: textColor),
            title: Text(
              context.l10n.settings,
              style: TextStyle(color: textColor),
            ),
            onTap: () {
              _closeDrawer(context);
              context.pushNamed(Routes.settings.name);
            },
          ),
          ListTile(
            leading: Icon(Icons.help_outline, color: textColor),
            title: Text(
              context.l10n.help,
              style: TextStyle(color: textColor),
            ),
            onTap: () {
              _closeDrawer(context);
              _openHelp(context);
            },
          ),
        ],
      ),
    );
  }
}
