import 'package:flutter/material.dart';

class VirementBancairePage extends StatelessWidget {
  final bool isAnnual;
  final double amount;

  const VirementBancairePage({
    super.key,
    required this.isAnnual,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final title = isAnnual ? 'Virement pour abonnement annuel' : 'Virement pour abonnement mensuel';

    return Scaffold(
      appBar: AppBar(title: const Text('Virement bancaire manuel')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Montant à payer : ${amount.toStringAsFixed(2)}€',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Coordonnées bancaires :'),
            const SizedBox(height: 8),
            const SelectableText(
              'Titulaire : NAVIA\n'
              'IBAN : FR76 3000 4000 5000 6000 7000 890\n'
              'BIC  : BNPAFRPP\n'
              'Réf. à indiquer : ABONNEMENT + votre email',
            ),
            const SizedBox(height: 24),
            const Text(
              'Après le virement, appuie sur “J’ai effectué le virement”. '
              'Nous validerons l’abonnement dès réception.',
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                // TODO: ouvrir un petit formulaire “preuve de virement” / contacter support
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nous vérifierons votre virement')),
                );
              },
              child: const Text('J’ai effectué le virement'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
