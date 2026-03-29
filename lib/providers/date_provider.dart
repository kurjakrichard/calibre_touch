import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final dateProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});
