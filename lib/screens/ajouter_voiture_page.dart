import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class AjouterVoiturePage extends StatefulWidget {
  const AjouterVoiturePage({super.key});

  @override
  State<AjouterVoiturePage> createState() => _AjouterVoiturePageState();
}

class _AjouterVoiturePageState extends State<AjouterVoiturePage> {
  final _formKey = GlobalKey<FormState>();

  final displayNameController = TextEditingController(); // Nom affiché (optionnel)
  final marqueController = TextEditingController();
  final modeleController = TextEditingController();
  final immatriculationController = TextEditingController();

  bool loading = false;
  int montantAbonnement = 0;

  @override
  void initState() {
    super.initState();
    _calculerMontant(); // afficher le montant actuel au démarrage
  }

  @override
  void dispose() {
    displayNameController.dispose();
    marqueController.dispose();
    modeleController.dispose();
    immatriculationController.dispose();
    super.dispose();
  }

  /// ────────────────────────────────────────────────────────────────
  /// Calcule le montant total (10€/voiture)
  /// ────────────────────────────────────────────────────────────────
  Future<void> _calculerMontant() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final res = await Supabase.instance.client
        .from('voitures')
        .select('id')
        .eq('owner_user_id', user.id);

    // ⚠️ res est un PostgrestList, count disponible directement
    final count = res.length;
    setState(() {
      // +1 pour la voiture en cours d’ajout
      montantAbonnement = (count + 1) * 10;
    });
  }

  /// ────────────────────────────────────────────────────────────────
  /// Validations simples
  /// ────────────────────────────────────────────────────────────────
  String? _validateNotEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ requis' : null;

  String? _validatePlate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ requis';
    final plate = v.trim().toUpperCase();
    final reg = RegExp(r'^[A-Z0-9\- ]{3,12}$'); // simple et robuste
    if (!reg.hasMatch(plate)) return 'Immatriculation invalide';
    return null;
  }

  /// ────────────────────────────────────────────────────────────────
  /// Ajoute une voiture pour l’utilisateur connecté
  /// ────────────────────────────────────────────────────────────────
  Future<void> _ajouterVoiture() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Session expirée. Reconnecte-toi.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);
    try {
      final supa = Supabase.instance.client;

      // Normaliser l’immat
      final immat = immatriculationController.text.trim().toUpperCase();

      // Vérifier l’unicité de l’immat pour ce propriétaire
      final exist = await supa
          .from('voitures')
          .select('id')
          .eq('owner_user_id', user.id)
          .eq('immatriculation', immat);

      if (exist.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('❌ Cette immatriculation existe déjà pour ton compte.')),
        );
        return;
      }

      // Données à insérer
      final data = {
        'owner_user_id': user.id,
        'immatriculation': immat,
        'display_driver_name':
            displayNameController.text.trim().isEmpty
                ? null
                : displayNameController.text.trim(),
        'marque': marqueController.text.trim().isEmpty
            ? null
            : marqueController.text.trim(),
        'modele': modeleController.text.trim().isEmpty
            ? null
            : modeleController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      // Insertion
      final insert = await supa
          .from('voitures')
          .insert(data)
          .select('id')
          .single();

      final voitureId = insert['id'];

      await _calculerMontant();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '✅ Voiture ajoutée. Abonnement total : $montantAbonnement €')),
      );

      // 👉 Si tu veux rediriger vers une page de paiement après ajout :
      // Navigator.pushNamed(context, '/paiement_abonnement', arguments: {
      //   'montant': montantAbonnement,
      //   'voitureId': voitureId,
      // });

      // Ou revenir au dashboard :
      Navigator.pop(context, {'added': true, 'voitureId': voitureId});
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erreur base : ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// ────────────────────────────────────────────────────────────────
  /// UI
  /// ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4D3E),
        title: const Text('Suivi Taxi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'add_car_title'.tr(), // “Ajouter une voiture”
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B4D3E),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Abonnement actuel : $montantAbonnement €',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 28),

              Text('display_name_label'.tr(),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              TextFormField(
                controller: displayNameController,
                decoration: _inputDecoration(hint: 'ex: Ahmed (optionnel)'),
              ),
              const SizedBox(height: 18),

              Text('brand_label'.tr(),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              TextFormField(
                controller: marqueController,
                decoration: _inputDecoration(hint: 'ex: Toyota'),
                validator: _validateNotEmpty,
              ),
              const SizedBox(height: 18),

              Text('model_label'.tr(),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              TextFormField(
                controller: modeleController,
                decoration: _inputDecoration(hint: 'ex: Yaris'),
                validator: _validateNotEmpty,
              ),
              const SizedBox(height: 18),

              Text('plate_label'.tr(),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              TextFormField(
                controller: immatriculationController,
                textCapitalization: TextCapitalization.characters,
                decoration: _inputDecoration(hint: 'AA-123-AA'),
                validator: _validatePlate,
                onChanged: (v) {
                  final up = v.toUpperCase();
                  if (up != v) {
                    final pos = immatriculationController.selection;
                    immatriculationController.value =
                        TextEditingValue(text: up, selection: pos);
                  }
                },
              ),
              const SizedBox(height: 28),

              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : _ajouterVoiture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4D3E),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'add_button'.tr(), // “Ajouter”
                            style: const TextStyle(
                                fontSize: 16, color: Colors.white),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
