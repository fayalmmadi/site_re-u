import 'package:flutter/material.dart';

class ClientsPage extends StatelessWidget {
  const ClientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commander un taxi')),
      body: const Center(
        child: Text('Page publique : commande de taxi (à implémenter)'),
      ),
    );
  }
}
