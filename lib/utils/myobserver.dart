import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class MyObserver extends ProviderObserver {

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    debugPrint('Provider ${context.provider} was initialized with $value');
  }

  @override
  void didDisposeProvider(ProviderObserverContext context, ) {
    debugPrint('Provider ${context.provider} was disposed');
  }

  @override
  void didUpdateProvider(
  ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    debugPrint('Provider ${context.provider} updated from $previousValue to $newValue');
  }

  @override
  void providerDidFail(
   ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('Provider ${context.provider} provider threw $error at $stackTrace');
  }
}
