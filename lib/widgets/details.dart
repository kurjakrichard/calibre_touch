import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/data_export.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import 'book_cover.dart';
import 'html_description.dart';
import 'book_actions.dart';
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
        : Align(
            alignment: AlignmentDirectional.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 48.0),
              child: Text(context.l10n.noBookSelected),
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
              topLeft(selectedBook, context),
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
              Flexible(flex: 2, child: topLeft(selectedBook, context)),
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
        // comments.text is HTML (Calibre stores descriptions that way).
        child: HtmlDescription(
          selectedBook.description,
          style: const TextStyle(fontSize: 13.0, height: 1.5),
        ),
      ),
    );
  }

  ///detail top right
  Column topRight(Book selectedBook, BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        text(selectedBook.title,
            size: 16, isBold: true, padding: const EdgeInsets.only(top: 16.0)),
        text(
          l10n.byAuthor(selectedBook.author),
          size: 12,
          padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
        ),
        if (selectedBook.seriesLabel.isNotEmpty)
          field(l10n.series, selectedBook.seriesLabel),
        if (selectedBook.publisher.isNotEmpty)
          field(l10n.publisher, selectedBook.publisher),
        // Like Calibre: "Tags: Fantasy, Epic, Adventure"
        if (selectedBook.tagList.isNotEmpty)
          field(l10n.tags, selectedBook.tagList.join(', ')),
        text(
          selectedBook.price,
          isBold: true,
          padding: const EdgeInsets.only(right: 8.0),
        ),
        RatingBar(rating: selectedBook.rating),
        const SizedBox(height: 32.0),
        Consumer(
          builder: (context, ref, _) {
            final readInApp = BookActions.canReadInApp(selectedBook,
                useBuiltIn: ref.watch(useBuiltInReaderProvider));
            return Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => BookActions.open(context, ref, selectedBook),
                icon: Icon(readInApp ? Icons.menu_book : Icons.open_in_new),
                label: Text(readInApp ? l10n.read : l10n.open),
              ),
              ElevatedButton(
                onPressed: () {
                  context.pushNamed(Routes.updateBook.name);
                },
                child: Text(l10n.editBook),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    BookActions.openFolder(context, ref, selectedBook),
                icon: const Icon(Icons.folder_open),
                label: Text(l10n.openFolder),
              ),
            ],
          );
          },
        )
      ],
    );
  }

  ///detail of book image and it's pages
  Column topLeft(Book selectedBook, BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: 360,
            child: Material(
              elevation: 15.0,
              shadowColor: Colors.yellow.shade900,
              child: BookCover(book: selectedBook, fit: BoxFit.fitWidth),
            ),
          ),
        ),
        text(context.l10n.pageCount(selectedBook.pages), size: 12)
      ],
    );
  }

  /// 'Label: value' line (e.g. Series, Publisher).
  Widget field(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ]),
          style: const TextStyle(color: mainFontColor, fontSize: 13),
        ),
      );

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
