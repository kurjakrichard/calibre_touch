import 'package:flutter_riverpod/flutter_riverpod.dart';

final class MyObserver extends ProviderObserver {

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    print('Provider ${context.provider} was initialized with $value');
  }

  @override
  void didDisposeProvider(ProviderObserverContext context, ) {
    print('Provider ${context.provider} was disposed');
  }

  @override
  void didUpdateProvider(
  ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    print('Provider ${context.provider} updated from $previousValue to $newValue');
  }

  @override
  void providerDidFail(
   ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    print('Provider ${context.provider} provider threw $error at $stackTrace');
  }
}
