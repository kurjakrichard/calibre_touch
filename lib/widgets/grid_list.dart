import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data_export.dart';
import '../providers/providers.dart';
import 'widgets.dart';

class GridList extends ConsumerWidget {
  const GridList({super.key, this.count = 1});

  final double count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Book> books = ref.watch(booksProvider).visibleBooks;
    int size = MediaQuery.of(context).size.width.round();

    ///create book tile hero
    createTile(Book book) => Hero(
          tag: book.id.toString(),
          child: Material(
            elevation: 15.0,
            child: InkWell(
              onDoubleTap: () => BookActions.showMenu(context, ref, book),
              onLongPress: () => BookActions.showMenu(context, ref, book),
              onTap: () => BookActions.select(context, ref, book),
              child: BookCover(book: book),
            ),
          ),
        );

    ///create book grid tiles
    final grid = CustomScrollView(
      primary: false,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverGrid.count(
            childAspectRatio: 2 / 3,
            crossAxisCount: (size / 150 / count).round(),
            mainAxisSpacing: 10.0,
            crossAxisSpacing: 10.0,
            children: books.map((book) => createTile(book)).toList(),
          ),
        )
      ],
    );

    return grid;
  }
}
