import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/path_provider.dart';
import 'book_datasource.dart';

final bookDatasourceProvider = Provider<BookDatasource>((ref) {
  // pathProvider is the single source of truth for the user's custom
  // library path; only fall back to the default when it's unset.
  final customPath = ref.watch(pathProvider);
  return BookDatasource(customPath: customPath.isEmpty ? null : customPath);
});
