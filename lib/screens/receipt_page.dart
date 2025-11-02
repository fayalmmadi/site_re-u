import 'package:flutter/material.dart';

class ReceiptPage extends StatelessWidget {
  const ReceiptPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu'),
        backgroundColor: const Color(0xFF084C28), // Vert sombre
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Suivi des taxis en temps réel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 20),
                  Text('Nom du conducteur : Ibrahim D.'),
                  SizedBox(height: 10),
                  Text('ID du taxi : TO-234-AB'),
                  SizedBox(height: 10),
                  Text('Date : 30 mai 2024'),
                  SizedBox(height: 10),
                  Text('Heure : 08:05'),
                  SizedBox(height: 10),
                  Text('Paiement : 3,50 €', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Action future pour téléchargement PDF
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF084C28),
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text("Télécharger le reçu (PDF)"),
            ),
            const SizedBox(height: 12),
            const Text(
              "Uniquement disponible en cas de connexion",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
