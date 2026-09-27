import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data_export.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';

/// Placeholder shown while the library path resolves, or when the book has
/// no cover.jpg in its folder.
const String placeholderCover = 'res/corel.jpg';

/// A book's cover, loaded from the file system the way Calibre stores it:
/// `<library>/<book.path>/cover.jpg`.
class BookCover extends ConsumerWidget {
  const BookCover({super.key, required this.book, this.fit = BoxFit.cover});

  final Book book;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = ref.watch(libraryRootProvider).value;
    if (root == null || book.path.isEmpty) return _placeholder();

    final coverPath = FileService.coverPathIn(root, book.path);
    return Image.file(
      File(coverPath),
      key: ValueKey(coverPath),
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Image.asset(placeholderCover, fit: fit);
}
