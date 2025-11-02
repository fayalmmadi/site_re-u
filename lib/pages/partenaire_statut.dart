import 'package:flutter/material.dart';
import 'pending_status_page.dart';

/// Route: '/partenaire_statut'
class PartenaireStatutPage extends StatelessWidget {
  const PartenaireStatutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PendingStatusPage(
      tableName: 'partenaires',
      roleLabel: 'Partenaire',
      dashboardRoute: '/partenaire_dashboard',
      signupRoute: '/inscription_partenaire',
    );
  }
}
