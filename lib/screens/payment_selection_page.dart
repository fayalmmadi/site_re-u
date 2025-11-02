import 'package:flutter/material.dart';
import 'carte_bancaire_page.dart';
import 'paypal_page.dart';
import 'virement_bancaire_page.dart';
import 'cinetpay_payment_page.dart';

class PaymentSelectionPage extends StatelessWidget {
  final double amount; // montant total à payer (déjà calculé)
  final bool isAnnual;

  const PaymentSelectionPage({
    super.key,
    required this.amount,
    required this.isAnnual,
  });

  String _title() => isAnnual ? 'Montant à payer (an)' : 'Montant à payer (mois)';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Paiement', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.brown,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.credit_card, size: 48, color: Colors.black),
                  const SizedBox(height: 10),
                  Text(_title(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
                  const SizedBox(height: 6),
                  Text(
                    '${amount.toStringAsFixed(2)}€',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text('Choisissez un moyen de paiement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _buildPaymentOption(
              icon: Icons.credit_card,
              title: 'Carte bancaire (Visa, Mastercard)',
              rightLogo: 'assets/images/visa_mastercard.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CarteBancairePage(isAnnual: isAnnual, amount: amount),
                  ),
                );
              },
            ),
            _buildPaymentOption(
              icon: Icons.smartphone,
              title: 'CinetPay',
              subtitle: 'Orange Money, Moov, Airtel, MTN…',
              rightLogo: 'assets/images/cinetpay_logo.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CinetPayPage(isAnnual: isAnnual, amount: amount),
                  ),
                );
              },
            ),
            _buildPaymentOption(
              iconImage: 'assets/images/PayPal1.png',
              title: 'PayPal',
              subtitle: 'Europe, diaspora, USA',
              rightLogo: 'assets/images/paypal.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PayPalPage(isAnnual: isAnnual, amount: amount),
                  ),
                );
              },
            ),
            _buildPaymentOption(
              icon: Icons.account_balance,
              title: 'Virement bancaire manuel',
              rightLogo: 'assets/images/virement.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VirementBancairePage(isAnnual: isAnnual, amount: amount),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  // Ajuste les assets si besoin
                  // Ces logos sont purement décoratifs
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    IconData? icon,
    String? iconImage,
    required String title,
    String? subtitle,
    required String rightLogo,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (icon != null)
              Icon(icon, size: 28, color: Colors.black)
            else
              Image.asset(iconImage ?? '', height: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  ]
                ],
              ),
            ),
            SizedBox(
              height: 36,
              width: 60,
              child: Image.asset(rightLogo, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}
