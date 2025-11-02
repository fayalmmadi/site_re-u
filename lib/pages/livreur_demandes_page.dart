import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ service centralisant l’UPDATE/INSERT côté livraisons
import '../services/livraisons_service.dart';

class LivreurDemandesPage extends StatefulWidget {
  const LivreurDemandesPage({
    super.key,
    required this.livreurId,
    this.isBlocked = false, // <- optionnel (par défaut false)
  });

  final String livreurId;
  final bool isBlocked;

  @override
  State<LivreurDemandesPage> createState() => _LivreurDemandesPageState();
}

class _LivreurDemandesPageState extends State<LivreurDemandesPage> {
  final supabase = Supabase.instance.client;
  final _svc = LivraisonsService(); // ✅ instance du service

  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _rows = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // ---------- helpers ----------
  double _commissionOf(num? price) {
    final p = (price ?? 0).toDouble();
    return double.parse((p * 0.10).toStringAsFixed(2));
  }

  String _money(String? code, num? amount) {
    final c = (code == null || code.isEmpty) ? 'EUR' : code;
    if (amount == null) return '$c —';
    try {
      return NumberFormat.simpleCurrency(name: c, decimalDigits: 2).format(amount);
    } catch (_) {
      return '$c ${amount.toStringAsFixed(2)}';
    }
  }

  String _maskPhone(String s) {
    final d = s.replaceAll(RegExp(r'\D'), '');
    if (d.length <= 4) return '••••';
    return '•••• ${d.substring(d.length - 4)}';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return Colors.green.shade100;
      case 'refused':
        return Colors.red.shade100;
      case 'expired':
        return Colors.orange.shade100;
      case 'done':
        return Colors.purple.shade100;
      default:
        return Colors.grey.shade300; // pending
    }
  }

  Widget _expiryBadge(Map<String, dynamic> r) {
    final status = (r['status'] ?? 'pending') as String;
    if (status != 'pending') return const SizedBox.shrink();

    final createdAt = DateTime.tryParse((r['created_at'] ?? '') as String? ?? '');
    if (createdAt == null) return const SizedBox.shrink();

    final deadline = createdAt.add(const Duration(hours: 1));
    final now = DateTime.now();
    if (now.isAfter(deadline)) {
      return const Text('Expirée', style: TextStyle(color: Colors.red));
    }
    final diff = deadline.difference(now);
    final mins = diff.inMinutes;
    final label = mins <= 1 ? 'Expire dans 1 min' : 'Expire dans $mins min';
    return Text(label, style: const TextStyle(color: Colors.orange));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _humanizeError(Object e) {
    // Essaie d'extraire un message lisible (ex: PostgrestException.message)
    try {
      final dynamic de = e;
      final msg = (de.message ?? de.toString()).toString();
      return msg; // garde "PAYWALL: ..." tel quel
    } catch (_) {
      return e.toString();
    }
  }

  // ---------- data ----------
  Future<List<Map<String, dynamic>>> _load() async {
    final List data = await supabase
        .from('livraison_demandes')
        .select(
          '''
          id, client_id, livreur_id,
          depart_adresse, arrivee_adresse,
          prix_propose, devise, status, accepted_at, created_at,
          client_phone, client_nom, client_pays,
          commission_amount,
          objet
          ''',
        )
        .eq('livreur_id', widget.livreurId)
        .order('created_at', ascending: false);

    _rows = data.cast<Map<String, dynamic>>();

    // Marquer automatiquement comme expirées si >1h (best-effort)
    final now = DateTime.now();
    for (final r in _rows) {
      if (r['status'] == 'pending') {
        final createdAt = DateTime.tryParse((r['created_at'] ?? '') as String? ?? '');
        if (createdAt != null && now.isAfter(createdAt.add(const Duration(hours: 1)))) {
          r['status'] = 'expired';
          // Mise à jour côté base en arrière-plan (ne bloque pas l'UI)
          supabase
              .from('livraison_demandes')
              .update({'status': 'expired'})
              .eq('id', r['id'] as String)
              .catchError((_) {});
        }
      }
    }

    return _rows;
  }

  Future<void> _refresh() async {
    final f = _load(); // recharge les données
    setState(() {
      _future = f; // met à jour l’état
    });
    await f; // attend la fin du chargement
  }
  // ---------- actions ----------
  Future<void> _accept(String demandeId) async {
    // Garde-fou UI supplémentaire (la base bloquera de toute façon si cap atteint)
    if (widget.isBlocked) {
      _showSnack("🔴 Solde atteint. Règle ton solde pour accepter une course.");
      return;
    }

    try {
      // Appel centralisé : fait l'UPDATE (et/ou l'INSERT) ; laisse remonter les erreurs
      await _svc.accepterLivraison(demandeId);

      _showSnack('✅ Demande acceptée');
      _changed = true;
      _refresh();
    } catch (e) {
      _showSnack(_humanizeError(e)); // ex: "PAYWALL: solde ... >= cap ..."
    }
  }

  Future<void> _refuse(String demandeId) async {
    final i = _rows.indexWhere((r) => r['id'] == demandeId);
    if (i == -1) return;

    final before = Map<String, dynamic>.from(_rows[i]);
    setState(() => _rows[i]['status'] = 'refused');

    try {
      await supabase
          .from('livraison_demandes')
          .update({'status': 'refused'})
          .eq('id', demandeId);

      _changed = true;
      _refresh();
      _showSnack('Demande refusée');
    } catch (e) {
      setState(() => _rows[i] = before);
      _showSnack(_humanizeError(e));
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Demandes'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting && _rows.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data ?? _rows;
            if (rows.isEmpty) {
              return const Center(child: Text('Aucune demande pour le moment.'));
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length + (widget.isBlocked ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  // Bandeau bloqué en tête si isBlocked==true
                  if (widget.isBlocked) {
                    if (i == 0) {
                      return Card(
                        color: Colors.red.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const ListTile(
                          leading: Icon(Icons.lock, color: Colors.red),
                          title: Text('Solde atteint — accès limité'),
                          subtitle: Text(
                            "Règle ton solde de commissions pour accepter de nouvelles demandes.",
                          ),
                        ),
                      );
                    }
                    // Décale l’index réel de la liste
                    i -= 1;
                  }

                  final r = rows[i];
                  final status = (r['status'] ?? 'pending') as String;

                  final pending = status == 'pending';
                  final accepted = status == 'accepted';
                  final refused = status == 'refused';
                  final done = status == 'done';
                  final expired = status == 'expired';

                  final depart = (r['depart_adresse'] ?? '—').toString();
                  final arrivee = (r['arrivee_adresse'] ?? '—').toString();
                  final prix = (r['prix_propose'] as num?);
                  final devise = (r['devise'] ?? 'EUR').toString();

                  final clientPhone = (r['client_phone'] ?? '').toString();
                  final phoneLabel = clientPhone.isEmpty
                      ? '—'
                      : (accepted ? clientPhone : _maskPhone(clientPhone));

                  final commission =
                      (r['commission_amount'] as num?) ?? _commissionOf(prix);

                  final objet = (r['objet'] ?? '').toString();

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '$depart → $arrivee',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(status),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(status),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (objet.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Objet : $objet',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          Row(
                            children: [
                              Text('Prix proposé : ${_money(devise, prix)}'),
                              const SizedBox(width: 12),
                              const Icon(Icons.phone, size: 16),
                              const SizedBox(width: 4),
                              Text(phoneLabel),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (pending) _expiryBadge(r),
                          const SizedBox(height: 10),

                          if (pending)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _refuse(r['id'] as String),
                                  child: const Text('Refuser'),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: widget.isBlocked
                                      ? 'Solde atteint — règle le solde pour accepter.'
                                      : 'Accepter la demande',
                                  child: ElevatedButton(
                                    onPressed: widget.isBlocked
                                        ? null // disabled visuel si bloqué
                                        : () => _accept(r['id'] as String),
                                    child: const Text('Accepter'),
                                  ),
                                ),
                              ],
                            )
                          else if (accepted)
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green),
                                const SizedBox(width: 6),
                                Text('Commission : ${_money(devise, commission)}'),
                              ],
                            )
                          else if (refused)
                            const Row(
                              children: [
                                Icon(Icons.cancel, color: Colors.red),
                                SizedBox(width: 6),
                                Text('Demande refusée'),
                              ],
                            )
                          else if (expired)
                            const Row(
                              children: [
                                Icon(Icons.hourglass_disabled, color: Colors.orange),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Demande expirée — le client va choisir un autre livreur.',
                                  ),
                                ),
                              ],
                            )
                          else if (done)
                            const Row(
                              children: [
                                Icon(Icons.flag, color: Colors.purple),
                                SizedBox(width: 6),
                                Text('Course terminée'),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
