// lib/screens/demandes_page.dart
import 'package:flutter/material.dart';
import '../services/livraisons_service.dart';

class DemandesPage extends StatefulWidget {
  const DemandesPage({super.key});
  @override
  State<DemandesPage> createState() => _DemandesPageState();
}

class _DemandesPageState extends State<DemandesPage> {
  final _svc = LivraisonsService();
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _svc.fetchOpenJobs();
  }

  Future<void> _refetch() async {
    setState(() => _future = _svc.fetchOpenJobs());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final jobs = snap.data as List<Map<String, dynamic>>;
        if (jobs.isEmpty) {
          return const Center(child: Text('Aucune demande libre pour le moment.'));
        }
        return ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, i) {
            final j = jobs[i];
            final estLibre = j['status'] == 'pending' && j['livreur_id'] == null;
            return ListTile(
              title: Text('Montant: ${j['montant'] ?? '-'}'),
              subtitle: Text('Créée le: ${j['created_at']}'),
              trailing: ElevatedButton(
                onPressed: (!_busy && estLibre)
                    ? () async {
                        setState(() => _busy = true);
                        try {
                          await _svc.accepterLivraison(j['id'] as String);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Demande acceptée ✅')),
                            );
                          }
                          await _refetch(); // rafraîchir la liste
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Impossible: ${e.toString()}')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      }
                    : null,
                child: const Text('Accepter'),
              ),
            );
          },
        );
      },
    );
  }
}
