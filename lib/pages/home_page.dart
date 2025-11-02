import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // style bouton réutilisable
  ButtonStyle _btn(Color c) => ElevatedButton.styleFrom(
        backgroundColor: c.withOpacity(0.92),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    // si déjà connecté, on va direct aux rôles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pushReplacementNamed(context, '/roles');
      }
    });

    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Image de fond ---
          const DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/bg_home.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // --- Overlay sombre ---
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.black87],
              ),
            ),
          ),

          // --- Contenu ---
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        'Suivi Taxi',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Simplifiez la gestion des taxis\net des livraisons',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // ---- Boutons publics ----
                      ElevatedButton.icon(
                        style: _btn(Colors.blue),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/commande-taxi'),
                        icon: const Icon(Icons.local_taxi),
                        label: const Text('Commander un taxi'),
                      ),
                      const SizedBox(height: 14),

                      ElevatedButton.icon(
                        style: _btn(Colors.teal),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/livraison-demande'),
                        icon: const Icon(Icons.local_shipping),
                        label: const Text('Demander une livraison'),
                      ),
                      const SizedBox(height: 14),

                      // ---- Accès espace privé (choix login/signup) ----
                      ElevatedButton.icon(
                        style: _btn(Colors.green),
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/acces-compte', // <- page intermédiaire
                        ),
                        icon: const Icon(Icons.lock),
                        label: const Text('Accéder à mon espace'),
                      ),

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
