import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'evaluate_livreur_page.dart';

class AcceptedListPage extends StatefulWidget {
  const AcceptedListPage({super.key, required this.clientId});
  final String clientId;

  @override
  State<AcceptedListPage> createState() => _AcceptedListPageState();
}

class _AcceptedListPageState extends State<AcceptedListPage> {
  final supa = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final List rows = await supa
        .from('livraison_demandes')
        .select('''
          id, client_id, livreur_id,
          depart_adresse, arrivee_adresse,
          prix_propose, devise, status, created_at, accepted_at,
          client_can_reject_until, client_seen_accepted,
          livreurs:livreur_id ( nom, prenom, phone )
        ''')
        .eq('client_id', widget.clientId)
        .inFilter('status', ['accepted','accepted_by_driver'])
        .order('accepted_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);

    final list = (rows as List)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Marquer ces acceptations comme "vues"
    final unseenIds = list
        .where((r) => r['client_seen_accepted'] == false)
        .map((r) => r['id'] as String)
        .toList();
    if (unseenIds.isNotEmpty) {
      await supa
          .from('livraison_demandes')
          .update({'client_seen_accepted': true})
          .inFilter('id', unseenIds);
    }
    return list;
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _reject(String demandeId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rejeter cette acceptation ?'),
        content: const Text(
          "Si tu as trouvé quelqu'un d'autre, tu peux rejeter dans l'heure suivant l’acceptation.\n"
          "Le livreur sera prévenu et aucune commission ne sera prise."
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui, rejeter')),
        ],
      ),
    );
    if (ok != true) return;

    await supa
        .from('livraison_demandes')
        .update({
          'status': 'client_rejected',
          'client_rejected_at': DateTime.now().toUtc().toIso8601String(),
          'client_seen_rejected': false, // pour déclencher le badge "Rejets"
        })
        .eq('id', demandeId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Acceptation rejetée.')),
    );
    _refresh();
  }

  String _fmtMoney(String code, num? amount) {
    final a = (amount ?? 0).toDouble();
    try {
      return NumberFormat.simpleCurrency(name: code, decimalDigits: a % 1 == 0 ? 0 : 2).format(a);
    } catch (_) {
      return '$code ${a.toStringAsFixed(a % 1 == 0 ? 0 : 2)}';
    }
  }

  Widget _countdown(DateTime until, VoidCallback onExpire) =>
      _RejectCountdown(until: until, onExpired: onExpire);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes acceptées')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return const Center(child: Text('Aucune acceptation pour le moment.'));
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final lv = (r['livreurs'] as Map?) ?? {};
                final prenom = (lv['prenom'] ?? '').toString();
                final nom    = (lv['nom'] ?? '').toString();
                final name   = ('$prenom $nom').trim().isEmpty ? 'Livreur' : ('$prenom $nom').trim();
                final phone  = (lv['phone'] ?? '—').toString();

                final createdAt  = DateTime.tryParse((r['created_at'] ?? '').toString());
                final acceptedAt = DateTime.tryParse((r['accepted_at'] ?? '').toString());
                final accAt      = acceptedAt ?? createdAt;
                final accLabel   = accAt == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(accAt);

                // Deadline : priorité à la colonne; sinon 1h après acceptation
                DateTime? rejectUntil = r['client_can_reject_until'] == null
                    ? (accAt == null ? null : accAt.add(const Duration(hours: 1)))
                    : DateTime.tryParse(r['client_can_reject_until'].toString());
                final canReject = rejectUntil != null && DateTime.now().isBefore(rejectUntil!);

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Félicitations 🎉', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${r['depart_adresse']} — ${r['arrivee_adresse']}',
                          style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      const SizedBox(height: 8),

                      Row(children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Livreur : $name')),
                        if (phone != '—') ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.phone, size: 18),
                          const SizedBox(width: 4),
                          Text(phone),
                        ]
                      ]),
                      const SizedBox(height: 6),

                      Row(children: [
                        const Icon(Icons.access_time, size: 18),
                        const SizedBox(width: 6),
                        Text('Acceptée le $accLabel'),
                        const Spacer(),
                        Text(_fmtMoney((r['devise'] ?? 'EUR').toString(), r['prix_propose'])),
                      ]),

                      if (canReject) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.timer_outlined, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: _countdown(rejectUntil!, () => setState(() {}))),
                        ]),
                      ],

                      const SizedBox(height: 10),

                      Row(children: [
                        if (canReject)
                          OutlinedButton.icon(
                            onPressed: () => _reject(r['id'] as String),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Rejeter'),
                          ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EvaluateLivreurPage(
                                  clientId: widget.clientId,
                                  prefilledDemande: r,
                                ),
                              ),
                            );
                          },
                          child: const Text('Noter'),
                        ),
                      ]),
                    ]),
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

class _RejectCountdown extends StatefulWidget {
  final DateTime until;
  final VoidCallback onExpired;
  const _RejectCountdown({required this.until, required this.onExpired});

  @override
  State<_RejectCountdown> createState() => _RejectCountdownState();
}

class _RejectCountdownState extends State<_RejectCountdown> {
  late Duration _left;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _compute();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _compute());
  }

  void _compute() {
    final now = DateTime.now().toUtc();
    final until = widget.until.toUtc();
    final left = until.difference(now);
    if (left <= Duration.zero) {
      _t?.cancel();
      setState(() => _left = Duration.zero);
      widget.onExpired();
    } else {
      setState(() => _left = left);
    }
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final h = _left.inHours;
    final m = _left.inMinutes % 60;
    final s = _left.inSeconds % 60;
    return Text('Temps restant pour rejeter : $h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}');
  }
}
