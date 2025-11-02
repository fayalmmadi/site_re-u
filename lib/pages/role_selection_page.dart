// lib/pages/role_selection_page.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  // 👉 Seuls ces emails voient le bouton Admin
  static const Set<String> _allowedAdminEmails = {
    'fayalmmadi@gmail.com',
  };

  bool get _isLoggedIn =>
      Supabase.instance.client.auth.currentSession != null;

  bool get _isAdminEmail {
    final email = Supabase.instance.client.auth.currentUser?.email
        ?.trim()
        .toLowerCase();
    return email != null && _allowedAdminEmails.contains(email);
  }

  // ------- Helper centralisé : upsert idempotent dans user_roles -------
  Future<void> _addRole(String uid, String role) async {
    await Supabase.instance.client.from('user_roles').upsert(
      {'user_id': uid, 'role': role},
      onConflict: 'user_id,role',
      ignoreDuplicates: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Si pas connecté -> on force le login puis on revient ici
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      Future.microtask(() {
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: {'next': '/roles'},
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fond (cover) + voile + blur
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.40),
                  BlendMode.darken,
                ),
                child: Image.asset('assets/bg_taxis.jpg', fit: BoxFit.cover),
              ),
            ),
          ),
          // Image décor (contain)
          IgnorePointer(
            ignoring: true,
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.95,
                heightFactor: 0.95,
                child: Opacity(
                  opacity: 0.75,
                  child: Image.asset('assets/bg_taxis.jpg', fit: BoxFit.contain),
                ),
              ),
            ),
          ),

          // Contenu
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.local_taxi, size: 42, color: Color(0xFF22C55E)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Bienvenue sur Suivi Taxi",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Choisissez un rôle. S’il n’est pas encore activé,\n"
                        "on vous demandera uniquement les infos de profil.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      const SizedBox(height: 28),

                      _primaryButton(
                        context: context,
                        label: "Commander un taxi",
                        icon: Icons.location_on,
                        onTap: () => Navigator.pushNamed(context, '/commande-taxi'),
                      ),
                      const SizedBox(height: 18),

                      _roleButton(context, 'Chauffeur', Icons.drive_eta, _goChauffeur),
                      const SizedBox(height: 12),
                      _roleButton(context, 'Propriétaire', Icons.directions_car, _goProprietaire), // alias
                      const SizedBox(height: 12),
                      _roleButton(context, 'Partenaire', Icons.groups_2_rounded, _goPartenaire),
                      const SizedBox(height: 12),
                      _roleButton(context, 'Livreur', Icons.delivery_dining, _goLivreur),
                      const SizedBox(height: 12),

                      // 👉 Bouton Admin visible uniquement pour l'email whitelisté
                      if (_isAdminEmail)
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/admin'),
                          icon: const Icon(Icons.admin_panel_settings, size: 22),
                          label: const Text('Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 4,
                            shadowColor: Colors.black38,
                          ),
                        ),

                      const SizedBox(height: 20),
                      TextButton.icon(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/', // Home
                          (route) => false,
                        ),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Retour à l’accueil"),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                      ),
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

  // ---------- Boutons UI ----------
  Widget _primaryButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 6,
        shadowColor: Colors.black45,
      ),
    );
  }

  Widget _roleButton(
    BuildContext context,
    String label,
    IconData icon,
    Future<void> Function(BuildContext) onTap,
  ) {
    return ElevatedButton.icon(
      onPressed: () => onTap(context),
      icon: Icon(icon, size: 22),
      label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF22C55E),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
        shadowColor: Colors.black38,
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Logique rôles ----------

  // Chauffeur : dashboard si rôle; sinon profil chauffeur (sans email/mdp)
  Future<void> _goChauffeur(BuildContext context) async {
    final s = Supabase.instance.client;
    final uid = s.auth.currentUser!.id;

    try {
      // rôle déjà présent → dashboard
      if (await _hasRole(uid, 'chauffeur')) {
        Navigator.pushReplacementNamed(context, '/chauffeur');
        return;
      }

      // profil chauffeur ?
      final Map<String, dynamic>? profil = await s
          .from('chauffeurs')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();

      if (profil != null) {
        await _addRole(uid, 'chauffeur');
        Navigator.pushReplacementNamed(context, '/chauffeur');
      } else {
        // même formulaire pour Chauffeur & Propriétaire
        Navigator.pushNamed(context, '/profil_chauffeur');
      }
    } catch (e) {
      _snack(context, "Erreur chauffeur : $e");
    }
  }

  // Propriétaire = alias exact de Chauffeur (même table, même form, même dashboard)
  Future<void> _goProprietaire(BuildContext context) async {
    return _goChauffeur(context);
  }

  // Partenaire : inscription + validation admin obligatoire
  Future<void> _goPartenaire(BuildContext context) async {
    final s = Supabase.instance.client;
    final uid = s.auth.currentUser!.id;

    try {
      final Map<String, dynamic>? p = await s
          .from('partenaires')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();

      if (p == null) {
        Navigator.pushNamed(context, '/inscription_partenaire');
        return;
      }

      final estValide = (p['est_valide'] as bool?) ?? false;
      final estBloque = (p['est_bloque'] as bool?) ?? false;

      if (estBloque) {
        _snack(context, "Votre compte partenaire est bloqué.");
        return;
      }
      if (!estValide) {
        Navigator.pushNamed(context, '/partenaire_statut'); // en attente
        return;
      }

      await _addRole(uid, 'partenaire');
      // si Chauffeur & Partenaire vont au même endroit, mets ici '/chauffeur'
      Navigator.pushReplacementNamed(context, '/partenaire_dashboard');
    } catch (e) {
      _snack(context, "Erreur partenaire : $e");
    }
  }

  // Livreur : profil obligatoire + décision admin (en attente/bloqué/ok)
  Future<void> _goLivreur(BuildContext context) async {
    final s = Supabase.instance.client;
    final uid = s.auth.currentUser!.id;

    try {
      // 1) Cherche un profil livreur pour cet user
      final Map<String, dynamic>? profil = await s
          .from('livreurs')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();

      // 2) S'il n'y a PAS de profil → formulaire
      if (profil == null) {
        Navigator.pushNamed(context, '/profil_livreur');
        return;
      }

      // 3) Statuts
      final bool estValide = (profil['est_valide'] as bool?) ?? false;
      final bool estBloque = (profil['est_bloque'] as bool?) ?? false;

      if (estBloque) {
        _snack(context, "Votre compte livreur est bloqué.");
        return;
      }

      if (!estValide) {
        Navigator.pushNamed(context, '/livreur_statut'); // attente
        return;
      }

      // 4) Validé → rôle + dashboard
      await _addRole(uid, 'livreur');
      Navigator.pushReplacementNamed(context, '/livreur_dashboard');
    } catch (e) {
      _snack(context, "Erreur livreur : $e");
    }
  }

  // Helper : vérifie dans user_roles
  Future<bool> _hasRole(String uid, String role) async {
    final s = Supabase.instance.client;
    final rows = await s
        .from('user_roles')
        .select('role')
        .eq('user_id', uid)
        .eq('role', role);
    return rows.isNotEmpty;
  }
}
