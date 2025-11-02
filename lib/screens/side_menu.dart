// Fichier : side_menu.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SideMenu extends StatefulWidget {
  final void Function(String voitureId)? onVoitureSelected;
  const SideMenu({super.key, this.onVoitureSelected});

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  List<Map<String, dynamic>> voitures = [];
  bool showVoitures = false;

  @override
  void initState() {
    super.initState();
    chargerVoitures();
  }

  Future<void> chargerVoitures() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final response = await Supabase.instance.client
        .from('voitures')
        .select()
        .eq('user_id', user.id);

    setState(() {
      voitures = List<Map<String, dynamic>>.from(response);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final nom = user?.userMetadata?['nom'] ?? 'Utilisateur';
    final email = user?.email ?? '';
    final initiales = nom.isNotEmpty ? nom[0].toUpperCase() : '?';

    return Drawer(
      child: Container(
        color: const Color(0xFF084C28),
        child: Column(
          children: [
            DrawerHeader(
              decoration:
                  const BoxDecoration(color: Color(0xFF084C28)),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Text(
                      initiales,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nom,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        Text(email,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.local_taxi, color: Colors.white),
              title:
                  const Text("Chauffeur", style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pushNamed(context, '/chauffeur'),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: const Text("Propriétaire",
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pushNamed(context, '/proprietaire'),
            ),
            ExpansionTile(
              leading: const Icon(Icons.directions_car, color: Colors.white),
              title: const Text("Mes voitures",
                  style: TextStyle(color: Colors.white)),
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
              collapsedTextColor: Colors.white,
              children: voitures.map((voiture) {
                return ListTile(
                  title: Text(voiture['nom'] ?? 'Voiture inconnue'),
                  onTap: () {
                    if (widget.onVoitureSelected != null) {
                      widget.onVoitureSelected!(voiture['id']);
                    }
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.mail, color: Colors.white),
              title: const Text("Contactez-nous",
                  style: TextStyle(color: Colors.white)),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
