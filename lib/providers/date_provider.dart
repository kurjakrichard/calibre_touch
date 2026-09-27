import 'package:flutter_riverpod/flutter_riverpod.dart';

class DateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    return DateTime.now();
  }

  void setDate(DateTime newValue) {
    state = newValue;
  }
}

final dateProvider = NotifierProvider<DateNotifier, DateTime>(
  DateNotifier.new,
);
