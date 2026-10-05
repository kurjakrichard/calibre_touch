import 'package:flutter/material.dart';
import '../utils/utils.dart';

class RatingBar extends StatelessWidget {
  final int starCount;
  final double rating;
  /// Star colour; null = the icon colour of the current theme.
  final Color? color;

  const RatingBar(
      {super.key,
      this.starCount = 5,
      this.rating = 0.0,
      this.color});

  ///create star
  Widget buildStar(BuildContext context, int index) {
    IconData icName = Icons.star;
    final starColor =
        color ?? IconTheme.of(context).color ?? ratingStarColor;
    Color icColor = starColor;

    if (index >= rating) {
      icName = Icons.star_border;
      icColor = starColor.withValues(alpha: emptyStarOpacity);
    } else if (index > rating - 1 && index < rating) {
      icName = Icons.star_half;
    }

    return Icon(icName, size: 16.0, color: icColor);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(starCount, (i) => buildStar(context, i)),
    );
  }
}
