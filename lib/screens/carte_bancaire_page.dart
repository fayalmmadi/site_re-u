import 'package:flutter/material.dart';

class CarteBancairePage extends StatelessWidget {
  final bool isAnnual;
  final double amount;

  const CarteBancairePage({
    super.key,
    required this.isAnnual,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final title = isAnnual ? 'Paiement annuel' : 'Paiement mensuel';

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement par carte')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Montant à payer : ${amount.toStringAsFixed(2)}€',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Text(
              'Ici, intègre ton formulaire/SDK de paiement (Stripe, etc.).',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: lancer le paiement carte puis, si succès, confirmer côté serveur
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exemple: paiement carte lancé')),
                );
              },
              icon: const Icon(Icons.credit_card),
              label: const Text('Payer maintenant'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
