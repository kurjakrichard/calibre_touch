import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

/// Standalone Settings screen, reachable any time from the drawer.
///
/// Holds every setting: language, library folder, dark theme and the
/// built-in reader switch. Only the library-folder part ([SettingsForm]) is
/// shared with the onboarding, so it behaves identically in both places.
class SettingsPage extends ConsumerWidget {
  static SettingsPage builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const SettingsPage();

  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isDark = ref.watch(modeProvider) == 'dark';
    final language = ref.watch(localeProvider).languageCode;
    final useBuiltInReader = ref.watch(useBuiltInReaderProvider);
    final openLastBook = ref.watch(openLastBookOnStartProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
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
                    DropdownMenuItem(
                        value: 'en', child: Text(l10n.languageEnglish)),
                    DropdownMenuItem(
                        value: 'hu', child: Text(l10n.languageHungarian)),
                  ],
                ),
              ),
              const Divider(),
              const SettingsForm(),
              const SizedBox(height: 24),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.darkTheme),
                subtitle: Text(l10n.darkThemeSubtitle),
                value: isDark,
                onChanged: (value) {
                  ref
                      .read(modeProvider.notifier)
                      .setMode(value ? 'dark' : 'light');
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.menu_book),
                title: Text(l10n.builtInReader),
                subtitle: Text(useBuiltInReader
                    ? l10n.builtInReaderOn(
                        [...BookDocuments.formatNames, 'PDF'].join(', '))
                    : l10n.builtInReaderOff),
                value: useBuiltInReader,
                onChanged: (value) =>
                    ref.read(useBuiltInReaderProvider.notifier).set(value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_stories_outlined),
                title: Text(l10n.openLastBook),
                subtitle: Text(l10n.openLastBookSubtitle),
                value: openLastBook,
                onChanged: (value) =>
                    ref.read(openLastBookOnStartProvider.notifier).set(value),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref
                      .read(sharedUtilityProvider)
                      .setIsFirstRun(complete: true);
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.goNamed(Routes.home.name);
                  }
                },
                child: Text(l10n.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
