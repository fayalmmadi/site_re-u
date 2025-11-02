import 'package:flutter/material.dart';

class PayPalPage extends StatelessWidget {
  final bool isAnnual;
  final double amount;

  const PayPalPage({
    super.key,
    required this.isAnnual,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final title = isAnnual ? 'Paiement annuel' : 'Paiement mensuel';

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement via PayPal')),
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
              'Ici, intègre le SDK/flow PayPal (Checkout/Smart Buttons…).',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: lancer le paiement PayPal puis, si succès, confirmer côté serveur
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exemple: paiement PayPal lancé')),
                );
              },
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Payer avec PayPal'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
