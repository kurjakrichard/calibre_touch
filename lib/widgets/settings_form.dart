import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'app_alerts.dart';

/// Library-folder picker + light/dark theme switcher.
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

  Future<void> _pickFolder() async {
    setState(() => _isLoading = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path != null) {
        // pathProvider is the single source of truth for the custom path;
        // watching it in build() below is what updates the UI.
        ref.read(pathProvider.notifier).setPath(path);
      }
    } catch (e) {
      if (mounted) {
        AppAlerts.displaySnackbar(context, 'Could not open folder picker: $e');
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
    final rawPath = ref.watch(pathProvider);
    final customPath = rawPath.isEmpty ? null : rawPath;
    final currentPath = customPath ?? _defaultPath ?? 'Loading…';
    final usingDefault = customPath == null;
    final isDark = ref.watch(modeProvider) == 'dark';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Where should Calibre Touch keep your books?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          usingDefault ? 'Using the default location:' : 'Using a custom folder:',
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
                child: const Text('Choose folder'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: usingDefault ? null : _useDefaultFolder,
                child: const Text('Use default'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, 
          title: const Text('Dark theme'),
          subtitle: const Text('Switch between light and dark appearance'),
          value: isDark,
          onChanged: (value) {
            ref.read(modeProvider.notifier).setMode(value ? 'dark' : 'light');
          },
        ),
      ],
    );
  }
}
