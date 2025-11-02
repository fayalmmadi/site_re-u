import 'package:flutter/material.dart';

class AccesPartenairePage extends StatelessWidget {
  const AccesPartenairePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF4F7),
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 6),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user, size: 60, color: Color(0xFF1B4D3E)),
              const SizedBox(height: 16),
              const Text(
                'Accès Partenaire',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sélectionnez une option pour continuer.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Bouton inscription
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/inscription_partenaire');
                  },
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text("S'inscrire", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4D3E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bouton connexion
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/login_partenaire');
                  },
                  icon: const Icon(Icons.lock, color: Colors.white),
                  label: const Text("Se connecter", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF081F4D),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Bouton retour
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/role-selection');
                },
                child: const Text(
                  "← Retour au choix des rôles",
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
