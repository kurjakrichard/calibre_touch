import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_export.dart';

// watch (not read): must rebuild when the library folder changes.
final bookRepositoryProvider = Provider<BookRepository>((ref) {
  final datasource = ref.watch(bookDatasourceProvider);
  return BookRepositoryImpl(datasource);
});
