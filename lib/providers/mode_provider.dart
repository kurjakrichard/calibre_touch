import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

class ModeNotifier extends Notifier<String> {
  @override
  String build() {
    final saved = ref.watch(sharedUtilityProvider).getMode();
    return saved.isEmpty ? 'light' : saved;
  }

  void setMode(String newValue) {
    ref.read(sharedUtilityProvider).setMode(
          mode: newValue,
        );
    state = ref.read(sharedUtilityProvider).getMode();
  }
}

final modeProvider = NotifierProvider<ModeNotifier, String>(
  ModeNotifier.new,
);
