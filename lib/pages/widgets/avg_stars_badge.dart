import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvgStarsBadge extends StatelessWidget {
  const AvgStarsBadge({super.key, required this.livreurId, this.showProWhenHigh = false});
  final String livreurId;
  final bool showProWhenHigh;

  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final List data = await supa.from('livreur_reviews').select('stars').eq('livreur_id', livreurId);
        return data.cast<Map<String, dynamic>>();
      }(),
      builder: (_, snap) {
        if (snap.hasError) return const Icon(Icons.error_outline, size: 16, color: Colors.redAccent);
        if (!snap.hasData) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.star_border, size: 16, color: Colors.amber),
              Icon(Icons.star_border, size: 16, color: Colors.amber),
              Icon(Icons.star_border, size: 16, color: Colors.amber),
              Icon(Icons.star_border, size: 16, color: Colors.amber),
              Icon(Icons.star_border, size: 16, color: Colors.amber),
            ],
          );
        }
        final rows = snap.data!;
        if (rows.isEmpty) return const _StarsRow(avg: 0, count: 0, pro: false);

        final stars = rows.map((e) => e['stars']).where((x) => x != null).map((x) => (x as num).toDouble()).toList();
        if (stars.isEmpty) return const _StarsRow(avg: 0, count: 0, pro: false);

        final avg = stars.reduce((a, b) => a + b) / stars.length;
        final pro = showProWhenHigh && avg >= 4.8;
        return _StarsRow(avg: avg, count: stars.length, pro: pro);
      },
    );
  }
}

class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.avg, required this.count, required this.pro});
  final double avg;
  final int count;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    int full = avg.floor();
    bool half = (avg - full) >= 0.25 && (avg - full) < 0.75;
    int empty = 5 - full - (half ? 1 : 0);

    List<Widget> icons = [];
    icons.addAll(List.generate(full, (_) => const Icon(Icons.star, size: 16, color: Colors.amber)));
    if (half) icons.add(const Icon(Icons.star_half, size: 16, color: Colors.amber));
    icons.addAll(List.generate(empty, (_) => const Icon(Icons.star_border, size: 16, color: Colors.amber)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...icons,
          const SizedBox(width: 6),
          Text(avg == 0 ? '—' : avg.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text('  ($count)', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          if (pro) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(999)),
              child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ),
    );
  }
}
