import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

/// Standalone Settings screen, reachable any time from the drawer.
///
/// Shares its content with the second onboarding page via [SettingsForm], so
/// library-folder and theme choices behave identically in both places.
class SettingsPage extends ConsumerWidget {
  static SettingsPage builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const SettingsPage();

  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: primary,
      appBar: AppBar(
        title: Text(context.l10n.settings),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
            children: [
              const SettingsForm(),
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
                child: Text(
                  context.l10n.done,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
