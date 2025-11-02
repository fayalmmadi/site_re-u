// lib/pages/pending_list_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingListPage extends StatefulWidget {
  const PendingListPage({super.key, required this.clientId});
  final String clientId;

  @override
  State<PendingListPage> createState() => _PendingListPageState();
}

class _PendingListPageState extends State<PendingListPage> {
  final supa = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // petit tick pour rafraîchir les compte-à-rebours
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final List rows = await supa
        .from('livraison_demandes')
        .select('id, created_at, depart_adresse, arrivee_adresse, prix_propose, devise, status')
        .eq('client_id', widget.clientId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  Duration _remaining(Map r) {
    final created = DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now();
    final expire = created.add(const Duration(hours: 1));
    final now = DateTime.now();
    return expire.difference(now);
  }

  String _fmtMoney(String code, num? amount) {
    final a = (amount ?? 0).toDouble();
    try {
      return NumberFormat.simpleCurrency(name: code, decimalDigits: a % 1 == 0 ? 0 : 2).format(a);
    } catch (_) {
      return '$code ${a.toStringAsFixed(a % 1 == 0 ? 0 : 2)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('En attente de réponse')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return const Center(child: Text("Aucune demande en attente."));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final left = _remaining(r);
                final expired = left.isNegative;
                final label = expired
                    ? 'Expirée — choisis un autre livreur'
                    : 'Expire dans ${left.inMinutes} min';

                return Card(
                  child: ListTile(
                    title: Text('${r['depart_adresse']} — ${r['arrivee_adresse']}'),
                    subtitle: Text(label),
                    trailing: Text(_fmtMoney((r['devise'] ?? 'EUR').toString(), r['prix_propose'])),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
