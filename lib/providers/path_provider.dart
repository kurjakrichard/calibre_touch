import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared_preferences_provider.dart';

class PathNotifier extends Notifier<String> {
  bool isMetadataDb = false;

  @override
  String build() {
    return ref.watch(sharedUtilityProvider).getPath();
  }

  void setPath(String newValue) {
    ref.read(sharedUtilityProvider).setPath(
          path: newValue,
        );
    state = ref.read(sharedUtilityProvider).getPath();
  }
}

final pathProvider = NotifierProvider<PathNotifier, String>(
  PathNotifier.new,
);
