import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/config.dart';
import '../data/data_export.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'rating_bar.dart';
import 'package:flutter/material.dart';

class Details extends ConsumerWidget {
  const Details({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Book? selectedBook = ref.watch(selectedBookProvider);

    return selectedBook != null
        ? ListView(
            padding: const EdgeInsets.only(right: 8),
            children: <Widget>[
              topContent(selectedBook, context),
              bottomContent(selectedBook)
            ],
          )
        : const Align(
            alignment: AlignmentDirectional.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 48.0),
              child: Text('Nincs könyv kiválasztva'),
            ));
  }

  Widget topContent(Book selectedBook, BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      var isWide = constraints.maxWidth > maxWidth / 3;
      if (!isWide) {
        return Container(
          padding: const EdgeInsets.only(bottom: 16.0, left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              topLeft(selectedBook),
              topRight(selectedBook, context),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(flex: 2, child: topLeft(selectedBook)),
              Flexible(flex: 3, child: topRight(selectedBook, context)),
            ],
          ),
        );
      }
    });
  }

  SizedBox bottomContent(Book selectedBook) {
    return SizedBox(
      height: 400,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          selectedBook.description,
          style: const TextStyle(fontSize: 13.0, height: 1.5),
        ),
      ),
    );
  }

  ///detail top right
  Column topRight(Book selectedBook, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        text(selectedBook.title,
            size: 16, isBold: true, padding: const EdgeInsets.only(top: 16.0)),
        text(
          'by ${selectedBook.author}',
          size: 12,
          padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
        ),
        text(
          selectedBook.price,
          isBold: true,
          padding: const EdgeInsets.only(right: 8.0),
        ),
        RatingBar(rating: selectedBook.rating),
        const SizedBox(height: 32.0),
        ElevatedButton(
          onPressed: () {
            context.push(RouteLocation.updateBook);
          },
          child: const Text('Edit book'),
        )
      ],
    );
  }

  ///detail of book image and it's pages
  Column topLeft(Book selectedBook) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: 360,
            child: Material(
              elevation: 15.0,
              shadowColor: Colors.yellow.shade900,
              child: Image(
                image: AssetImage(selectedBook.image),
                fit: BoxFit.fitWidth,
              ),
            ),
          ),
        ),
        text('${selectedBook.pages} pages', size: 12)
      ],
    );
  }

  ///create text widget
  Padding text(String data,
          {num size = 14,
          EdgeInsetsGeometry padding = EdgeInsets.zero,
          bool isBold = false}) =>
      Padding(
        padding: padding,
        child: Text(
          data,
          style: TextStyle(
              color: mainFontColor,
              fontSize: size.toDouble(),
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
        ),
      );
}
