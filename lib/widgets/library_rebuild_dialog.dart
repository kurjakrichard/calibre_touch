import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import '../l10n/l10n.dart';
import '../providers/providers.dart';

/// "metadata.db is damaged - rebuild it from the metadata.opf files?"
///
/// Shown by HomePage when loading the library fails because metadata.db
/// is damaged (`LibraryLoadError.damagedDatabase`), and from the
/// "Rebuild database" button of LibraryEmptyView.
class LibraryRebuildDialog {
  LibraryRebuildDialog._();

  /// True while a question / rebuild is on screen (never two at once).
  static bool _active = false;

  /// Asks the user, and rebuilds the database if they say yes.
  static Future<void> offer(BuildContext context, WidgetRef ref) async {
    if (_active) return;
    _active = true;
    try {
      final l10n = context.l10n;
      final rebuild = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(l10n.databaseDamagedTitle),
          content: Text(l10n.databaseDamagedText),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.rebuildDatabase),
            ),
          ],
        ),
      );
      if (rebuild == true && context.mounted) await _rebuild(context, ref);
    } finally {
      _active = false;
    }
  }

  /// Rebuilds with a progress dialog, then shows what happened.
  static Future<void> _rebuild(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<(int, int)?>(null);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.rebuildDatabase),
          content: ValueListenableBuilder<(int, int)?>(
            valueListenable: progress,
            builder: (context, value, _) {
              final (done, total) = value ?? (0, 0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.rebuildingDatabase),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                      value: total == 0 ? null : done / total),
                  if (total > 0) ...[
                    const SizedBox(height: 8),
                    Text('$done / $total'),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );

    String title;
    final lines = <String>[];
    List<String> failedFolders = const [];
    try {
      final result = await ref
          .read(booksProvider.notifier)
          .rebuildFromOpf(onProgress: (done, total) {
        progress.value = (done, total);
      });
      title = l10n.rebuildDone(result.books);
      if (result.renumbered > 0) {
        lines.add(l10n.rebuildRenumbered(result.renumbered));
      }
      if (result.backupPath != null) {
        lines.add(l10n.rebuildBackup(p.basename(result.backupPath!)));
      }
      if (result.failedFolders.isNotEmpty) {
        lines.add(l10n.rebuildSkipped(result.failedFolders.length));
        failedFolders = result.failedFolders;
      }
    } catch (e) {
      debugPrint('Rebuild from metadata.opf failed: $e');
      title = l10n.rebuildFailed('$e');
    } finally {
      navigator.pop(); // the progress dialog
      progress.dispose();
    }

    if (!navigator.mounted) return;
    await showDialog<void>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: lines.isEmpty
            ? null
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(line),
                      ),
                    for (final folder in failedFolders)
                      SelectableText('• $folder',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }
}
