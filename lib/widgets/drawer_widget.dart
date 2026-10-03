import 'package:calibre_touch/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import 'book_actions.dart';

class DrawerWidget extends ConsumerWidget {
  const DrawerWidget({super.key});

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
    final disabledColor = buttoncolor.withValues(alpha: 0.5);

    return Drawer(
      backgroundColor: secondary,
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
                        style: const TextStyle(
                            color: buttoncolor,
                            fontSize: 16,
                            height: 2,
                            overflow: TextOverflow.clip),
                      ),
                    ),
                  ],
                )),
          ),
          ListTile(
            enabled: lastBook != null,
            leading: Icon(Icons.menu_book_outlined,
                color: lastBook != null ? buttoncolor : disabledColor),
            title: Text(
              context.l10n.continueReading,
              style: TextStyle(
                  color: lastBook != null ? buttoncolor : disabledColor),
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
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: buttoncolor),
            title: Text(
              context.l10n.settings,
              style: const TextStyle(color: buttoncolor),
            ),
            onTap: () {
              _closeDrawer(context);
              context.pushNamed(Routes.settings.name);
            },
          ),
        ],
      ),
    );
  }
}
