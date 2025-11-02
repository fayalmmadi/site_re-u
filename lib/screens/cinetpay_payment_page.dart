import 'package:flutter/material.dart';

class CinetPayPage extends StatelessWidget {
  final bool isAnnual;
  final double amount;

  const CinetPayPage({
    super.key,
    required this.isAnnual,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final title = isAnnual ? 'Paiement annuel' : 'Paiement mensuel';

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement via CinetPay')),
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
              'Ici, intègre le flow CinetPay (Mobile Money, Moov, Orange, Airtel, MTN…).',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: lancer le paiement CinetPay puis, si succès, confirmer côté serveur
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exemple: paiement CinetPay lancé')),
                );
              },
              icon: const Icon(Icons.smartphone),
              label: const Text('Payer avec CinetPay'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
