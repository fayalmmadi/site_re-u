import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RejectedListPage extends StatelessWidget {
  const RejectedListPage({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;

    Future<List<Map<String, dynamic>>> _load() async {
      final List rows = await supa
          .from('livraison_demandes')
          .select('''
            id, created_at, client_rejected_at,
            depart_adresse, arrivee_adresse, status,
            client_seen_rejected,
            livreurs:livreur_id ( nom, prenom, phone )
          ''')
          .eq('client_id', clientId)
          .inFilter('status', ['client_rejected','canceled_by_client'])
          .order('client_rejected_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false);

      final list = (rows as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Marquer comme "vu" pour cet onglet
      final unseenIds = list
          .where((r) => r['client_seen_rejected'] == false)
          .map((r) => r['id'] as String)
          .toList();
      if (unseenIds.isNotEmpty) {
        await supa
            .from('livraison_demandes')
            .update({'client_seen_rejected': true})
            .inFilter('id', unseenIds);
      }

      return list;
    }

    String _fmtDate(String? iso) {
      final d = DateTime.tryParse(iso ?? '');
      return d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Rejets d'acceptation")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('Aucun rejet.'));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final lv = (r['livreurs'] as Map?) ?? {};
              final driver = ([lv['prenom'] ?? '', lv['nom'] ?? '']
                              .where((s) => s.toString().trim().isNotEmpty)
                              .join(' ')).trim();
              final when = r['client_rejected_at']?.toString() ?? r['created_at']?.toString();

              return ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Acceptation rejetée'),
                subtitle: Text(
                  "${r['depart_adresse']} → ${r['arrivee_adresse']}\n"
                  "Par toi, le ${_fmtDate(when)}"
                  "${driver.isEmpty ? '' : "\nLivreur : $driver"}",
                ),
              );
            },
          );
        },
      ),
    );
  }
}
