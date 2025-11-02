import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EvaluateLivreurPage extends StatefulWidget {
  const EvaluateLivreurPage({
    super.key,
    required this.clientId,          // <- id de TA table clients
    required this.prefilledDemande,  // doit contenir au moins id, livreur_id
  });

  final String clientId;
  final Map<String, dynamic> prefilledDemande;

  @override
  State<EvaluateLivreurPage> createState() => _EvaluateLivreurPageState();
}

class _EvaluateLivreurPageState extends State<EvaluateLivreurPage> {
  final supa = Supabase.instance.client;

  int _rating = 3; // 1..3
  final _comment = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final d = widget.prefilledDemande;
      final livreurId = (d['livreur_id'] ?? d['livreurId'] ?? '').toString();
      final demandeId = (d['id'] ?? '').toString();

      if (livreurId.isEmpty || demandeId.isEmpty) {
        throw 'Données manquantes (livreurId/demandeId).';
      }

      // INSERT simple (pas d’UPSERT)
      await supa.from('livreur_reviews').insert({
        'client_id' : widget.clientId, // <- id de TA table clients
        'livreur_id': livreurId,
        'demande_id': demandeId,
        'stars'     : _rating,
        'comment'   : _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci pour votre avis !')),
      );
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous avez déjà noté cette demande.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _threeStarPicker() {
    Widget chip(int value, String label) {
      final sel = _rating == value;
      return ChoiceChip(
        label: Text(label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: sel ? Colors.white : Colors.black,
            )),
        selected: sel,
        selectedColor: const Color(0xFF22C55E),
        onSelected: (_) => setState(() => _rating = value),
      );
    }

    return Wrap(
      spacing: 8,
      children: [chip(1, '★'), chip(2, '★★'), chip(3, '★★★')],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.prefilledDemande;
    final lv = (d['livreurs'] as Map?) ?? {};
    final driverName = ([lv['prenom'] ?? '', lv['nom'] ?? '']
            .where((e) => e.toString().trim().isNotEmpty)
            .join(' '))
        .trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Évaluer un livreur')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(driverName.isEmpty ? 'Livreur' : driverName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '${d['depart_adresse'] ?? ''} → ${d['arrivee_adresse'] ?? ''}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            const Text('Ta note (1 à 3 étoiles) :',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _threeStarPicker(),
            const SizedBox(height: 16),
            const Text('Commentaire (facultatif)'),
            const SizedBox(height: 6),
            TextField(
              controller: _comment,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ex: ponctuel, serviable…',
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.send),
                label: Text(_saving ? 'Envoi…' : 'Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
