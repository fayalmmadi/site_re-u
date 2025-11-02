import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/star_rating.dart';

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({
    super.key,
    required this.livreurId,
    required this.livreurName,
  });

  final String livreurId;
  final String livreurName;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  final supa = Supabase.instance.client;

  Map<String, dynamic> _rating = const {};
  List<Map<String, dynamic>> _reviews = const [];
  bool _loading = true;
  String? _error;

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Agrégats
      final ratingRow = await supa
          .from('v_livreurs_ratings')
          .select()
          .eq('livreur_id', widget.livreurId)
          .maybeSingle();

      // 2) Liste des avis via RPC
      final rpcRes = await supa.rpc('get_livreur_reviews', params: {
        'livreur': widget.livreurId,
      });

      // cast robuste
      final list = (rpcRes is List)
          ? rpcRes
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _rating = ratingRow ?? const {};
        _reviews = list;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalStars = (_rating['total_stars'] as num? ?? 0).toInt();
    final monthStars = (_rating['month_stars'] as num? ?? 0).toInt();
    final count = (_rating['reviews_count'] as num? ?? 0).toInt();
    const maxStars = 500;
    final avg5 = (maxStars <= 0)
        ? '0.0'
        : (totalStars / maxStars * 5).clamp(0, 5).toStringAsFixed(1);

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Erreur de chargement :\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (count == 0) {
      content = const Center(child: Text("Aucun avis pour l'instant."));
    } else {
      content = ListView.separated(
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemCount: 1 + _reviews.length,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StarRating(
                      totalStars: totalStars,
                      monthStars: monthStars,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text('$avg5 / 5  ($count avis)'),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Ce mois-ci : $monthStars points collectés'),
              ],
            );
          }

          final r = _reviews[i - 1];
          final fullName = ([r['prenom'] ?? '', r['nom'] ?? '']
                  .where((s) => s.toString().trim().isNotEmpty)
                  .join(' '))
              .trim();

          final stars = (r['stars'] as num? ?? 0).toInt();
          final comment = (r['comment']?.toString().trim().isNotEmpty == true)
              ? r['comment'].toString()
              : '(sans commentaire)';

          return ListTile(
            leading: Text(
              '★' * stars,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            title: Text(comment),
            subtitle: Text(
              '${fullName.isEmpty ? "Client" : fullName} · ${_fmtDate(r['created_at']?.toString())}',
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Avis · ${widget.livreurName}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: content,
      ),
    );
  }
}
