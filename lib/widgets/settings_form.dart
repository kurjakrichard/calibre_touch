import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'app_alerts.dart';

/// Language picker + library-folder picker + light/dark theme switcher +
/// built-in reader vs. system app switch for EPUB/PDF.
///
/// Used both by the standalone [SettingsPage] (reachable later from the
/// drawer) and embedded as a page inside onboarding, so the two never drift
/// apart.
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
    final isDark = ref.watch(modeProvider) == 'dark';
    final language = ref.watch(localeProvider).languageCode;
    final useBuiltInReader = ref.watch(useBuiltInReaderProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.language),
          title: Text(l10n.language),
          subtitle: Text(l10n.languageSubtitle),
          trailing: DropdownButton<String>(
            value: language,
            underline: const SizedBox.shrink(),
            onChanged: (code) {
              if (code != null) {
                ref.read(localeProvider.notifier).setLanguage(code);
              }
            },
            items: [
              DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
              DropdownMenuItem(
                  value: 'hu', child: Text(l10n.languageHungarian)),
            ],
          ),
        ),
        const Divider(),
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
          style: const TextStyle(fontSize: 14, color: mainFontColor),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: secondary,
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
        const SizedBox(height: 24),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, 
          title: Text(l10n.darkTheme),
          subtitle: Text(l10n.darkThemeSubtitle),
          value: isDark,
          onChanged: (value) {
            ref.read(modeProvider.notifier).setMode(value ? 'dark' : 'light');
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.menu_book),
          title: Text(l10n.builtInReader),
          subtitle: Text(useBuiltInReader
              ? l10n.builtInReaderOn
              : l10n.builtInReaderOff),
          value: useBuiltInReader,
          onChanged: (value) =>
              ref.read(useBuiltInReaderProvider.notifier).set(value),
        ),
      ],
    );
  }
}
