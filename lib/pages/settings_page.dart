import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  static SettingsPage builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const SettingsPage();

  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? _customPath;
  String? _defaultPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _customPath = ref.read(sharedUtilityProvider).getPath();
    if (_customPath != null && _customPath!.isEmpty) _customPath = null;
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
        setState(() => _customPath = path);
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
    setState(() => _customPath = null);
  }

  Future<void> _continue() async {
    ref.read(sharedUtilityProvider).setPath(path: _customPath ?? '');
    ref.read(sharedUtilityProvider).setOnboardingComplete(complete: true);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(Routes.home.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _customPath ?? _defaultPath ?? 'Loading…';
    final usingDefault = _customPath == null;

    return Scaffold(
      backgroundColor: primary,
      appBar: AppBar(
        title: const Text('Library location'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Where should Calibre Touch keep your books?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                usingDefault
                    ? 'Using the default location:'
                    : 'Using a custom folder:',
                style: const TextStyle(fontSize: 14, color: mainFontColor),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(currentPath),
              ),
              const SizedBox(height: 24),
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
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttoncolor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _continue,
                child: const Text(
                  'Continue',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
