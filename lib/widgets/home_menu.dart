import 'package:flutter/material.dart';
import 'book_views.dart';

/// The home page's app bar menu (⋮). Add new entries to [menuChildren]:
/// a [MenuItemButton] for a single action, a [SubmenuButton] for a group.
class HomeMenuButton extends StatelessWidget {
  const HomeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: const [
        BookViewSubmenu(),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        icon: const Icon(Icons.more_vert),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
