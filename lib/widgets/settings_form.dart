import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'app_alerts.dart';

/// Library-folder picker (default location or a custom folder).
///
/// Used both by the standalone [SettingsPage] (reachable later from the
/// drawer) and embedded as a page inside onboarding, so the two never drift
/// apart. All other settings (language, theme, reader) live directly on the
/// [SettingsPage].
class SettingsForm extends ConsumerStatefulWidget {
  const SettingsForm({super.key});

  @override
  ConsumerState<SettingsForm> createState() => SettingsFormState();
}

class SettingsFormState extends ConsumerState<SettingsForm> {
  String? _defaultPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultPath();
  }

  Future<void> _loadDefaultPath() async {
    final defaultPath = await FileService().defaultLibraryRoot();
    if (mounted) setState(() => _defaultPath = defaultPath);
  }

  /// Makes sure we can read/write a custom folder on Android.
  /// Returns true if access is granted; otherwise tells the user why not.
  Future<bool> _ensureStorageAccess() async {
    final access = await StoragePermission.ensure();
    if (!mounted) return false;
    final l10n = context.l10n;
    switch (access) {
      case StorageAccess.granted:
        return true;
      case StorageAccess.denied:
        AppAlerts.displaySnackbar(context, l10n.storageNeeded);
      case StorageAccess.restricted:
        AppAlerts.displaySnackbar(context, l10n.storageRestricted);
      case StorageAccess.permanentlyDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.storageDenied),
            action: SnackBarAction(
              label: l10n.settings,
              onPressed: StoragePermission.openSettings,
            ),
          ),
        );
    }
    return false;
  }

  Future<void> _pickFolder() async {
    setState(() => _isLoading = true);
    try {
      if (!await _ensureStorageAccess()) return;
      final path = await FilePicker.getDirectoryPath();
      if (path != null) {
        // pathProvider is the single source of truth for the custom path;
        // watching it in build() below is what updates the UI.
        ref.read(pathProvider.notifier).setPath(path);
      }
    } catch (e) {
      if (mounted) {
        AppAlerts.displaySnackbar(context, context.l10n.folderPickerError('$e'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _useDefaultFolder() {
    ref.read(pathProvider.notifier).setPath('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rawPath = ref.watch(pathProvider);
    final customPath = rawPath.isEmpty ? null : rawPath;
    final currentPath = customPath ?? _defaultPath ?? l10n.loading;
    final usingDefault = customPath == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          l10n.libraryQuestion,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          usingDefault ? l10n.usingDefaultLocation : l10n.usingCustomFolder,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (Theme.of(context).brightness == Brightness.dark ? darkListBackground : panelColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(currentPath, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _pickFolder,
                child: Text(l10n.chooseFolder),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: usingDefault ? null : _useDefaultFolder,
                child: Text(l10n.useDefault),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _LibraryLocationWarning(text: l10n.libraryLocationWarning),
      ],
    );
  }
}

/// Warns that a library on a network share or in a cloud-synced folder
/// (OneDrive, Google Drive, Dropbox…) can get corrupted – SQLite's locking
/// isn't reliable there. Calibre gives the same advice.
class _LibraryLocationWarning extends StatelessWidget {
  const _LibraryLocationWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
