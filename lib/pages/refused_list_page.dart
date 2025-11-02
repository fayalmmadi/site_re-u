import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RefusedListPage extends StatelessWidget {
  const RefusedListPage({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;

    Future<List<Map<String, dynamic>>> _load() async {
      final List rows = await supa
          .from('livraison_demandes')
          .select('''
            id, created_at, depart_adresse, arrivee_adresse, status,
            client_seen_refused,
            livreurs:livreur_id ( nom, prenom, phone )
          ''')
          .eq('client_id', clientId)
          .inFilter('status', ['refused','refused_by_driver'])
          .order('created_at', ascending: false);

      final list = (rows as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Marquer comme "vu" pour cet onglet
      final unseenIds = list
          .where((r) => r['client_seen_refused'] == false)
          .map((r) => r['id'] as String)
          .toList();
      if (unseenIds.isNotEmpty) {
        await supa
            .from('livraison_demandes')
            .update({'client_seen_refused': true})
            .inFilter('id', unseenIds);
      }

      return list;
    }

    String _fmtDate(String? iso) {
      final d = DateTime.tryParse(iso ?? '');
      return d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Demandes refusées')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('Rien ici.'));

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
              final phone = (lv['phone'] ?? '—').toString();

              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('Refusé par ${driver.isEmpty ? "le livreur" : driver}'),
                subtitle: Text(
                  "${r['depart_adresse']} → ${r['arrivee_adresse']}\n"
                  "Le ${_fmtDate(r['created_at']?.toString())}",
                ),
                trailing: phone == '—' ? null : Text(phone),
              );
            },
          );
        },
      ),
    );
  }
}
