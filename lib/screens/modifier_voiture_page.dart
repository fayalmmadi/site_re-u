import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModifierVoiturePage extends StatefulWidget {
  final Map voiture;

  const ModifierVoiturePage({Key? key, required this.voiture}) : super(key: key);

  @override
  State<ModifierVoiturePage> createState() => _ModifierVoiturePageState();
}

class _ModifierVoiturePageState extends State<ModifierVoiturePage> {
  late TextEditingController nomController;

  @override
  void initState() {
    super.initState();
    nomController = TextEditingController(text: widget.voiture['nom']);
  }

  @override
  void dispose() {
    nomController.dispose();
    super.dispose();
  }

  Future<void> _enregistrerModifications() async {
    final voitureId = widget.voiture['id'];
    final nouveauNom = nomController.text.trim();

    if (nouveauNom.isNotEmpty) {
      await Supabase.instance.client
          .from('voitures')
          .update({'nom': nouveauNom})
          .eq('id', voitureId);
      Navigator.pop(context); // Retour à la page précédente
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modifier la voiture")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: nomController,
              decoration: const InputDecoration(labelText: 'Nom de la voiture'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _enregistrerModifications,
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
