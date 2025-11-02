import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.totalStars,   // nombre total de points collectés (ex: somme des notes 1..3)
    required this.monthStars,   // nombre de points collectés ce mois
    this.size = 20,
    this.color = Colors.amber,
    this.minMonthStars = 50,    // minimum requis par mois
    this.maxStars = 500,        // seuil total = 5 étoiles pleines
    this.showWarning = true,    // afficher ou non l’avertissement
  });

  final int totalStars;
  final int monthStars;
  final double size;
  final Color color;
  final int minMonthStars;
  final int maxStars;
  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    // Vérification du minimum mensuel
    if (monthStars < minMonthStars) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showWarning)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.warning, color: Colors.red, size: 18),
            ),
          Text(
            "Pas assez d'avis ce mois-ci",
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      );
    }

    // Conversion totalStars → note sur 5
    final ratio = (totalStars / maxStars).clamp(0, 1);
    final noteSur5 = ratio * 5;

    final full = noteSur5.floor();
    final half = (noteSur5 - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < full; i++)
          Icon(Icons.star, size: size, color: color),
        if (half == 1)
          Icon(Icons.star_half, size: size, color: color),
        for (int i = 0; i < empty; i++)
          Icon(Icons.star_border, size: size, color: color),
      ],
    );
  }
}
