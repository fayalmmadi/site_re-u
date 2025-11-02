import 'package:flutter/material.dart';

class LivreurCard extends StatelessWidget {
  const LivreurCard({super.key, required this.row, required this.onPick});
  final Map<String,dynamic> row;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final dist = (row['distance_km'] as num?)?.toDouble() ?? 0;
    final eta = (dist / 0.5).round(); // ~30 km/h
    return ListTile(
      leading: const Icon(Icons.local_shipping),
      title: Text(row['display_name'] ?? 'Livreur'),
      subtitle: Text('${dist.toStringAsFixed(1)} km • ~$eta min'),
      trailing: ElevatedButton(onPressed: onPick, child: const Text('Choisir')),
    );
  }
}
