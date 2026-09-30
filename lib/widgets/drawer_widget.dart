import 'package:calibre_touch/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/l10n.dart';

class DrawerWidget extends StatelessWidget {
  const DrawerWidget({super.key});

  @override
  Widget build(BuildContext context) {
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
            leading: const Icon(Icons.settings_outlined, color: buttoncolor),
            title: Text(
              context.l10n.settings,
              style: const TextStyle(color: buttoncolor),
            ),
            onTap: () {
              // On phones/tablets this widget is the Scaffold's slide-out
              // drawer: close it first, otherwise it is still open when the
              // user comes back from Settings. On desktop it is embedded in
              // the page body (never "open"), so nothing is closed there.
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold != null && scaffold.isDrawerOpen) {
                scaffold.closeDrawer();
              }
              context.pushNamed(Routes.settings.name);
            },
          ),
        ],
      ),
    );
  }
}
