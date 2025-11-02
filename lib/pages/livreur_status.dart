import 'package:flutter/material.dart';
import 'pending_status_page.dart';

/// Route: '/livreur_statut'
class LivreurStatutPage extends StatelessWidget {
  const LivreurStatutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PendingStatusPage(
      tableName: 'livreurs',
      roleLabel: 'Livreur',
      dashboardRoute: '/livreur_dashboard',
      signupRoute: '/profil_livreur', // ta page d’inscription livreur
    );
  }
}
