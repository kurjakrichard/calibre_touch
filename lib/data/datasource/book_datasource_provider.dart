import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/path_provider.dart';
import 'book_datasource.dart';

/// One [BookDatasource] per library folder.
///
/// Watching [pathProvider] means a folder change disposes this provider:
/// the old database is closed in onDispose and a fresh datasource is built
/// for the new folder. Everything that watches this (repository -> books)
/// rebuilds in turn.
final bookDatasourceProvider = Provider<BookDatasource>((ref) {
  final customPath = ref.watch(pathProvider);
  final datasource =
      BookDatasource(customPath: customPath.isEmpty ? null : customPath);
  ref.onDispose(datasource.close);
  return datasource;
});
