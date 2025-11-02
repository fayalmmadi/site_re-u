import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilChauffeurPage extends StatefulWidget {
  const ProfilChauffeurPage({super.key});
  @override
  State<ProfilChauffeurPage> createState() => _ProfilChauffeurPageState();
}

class _ProfilChauffeurPageState extends State<ProfilChauffeurPage> {
  final _formKey = GlobalKey<FormState>();
  final prenomCtrl = TextEditingController();
  final nomCtrl    = TextEditingController();
  final telCtrl    = TextEditingController();     // sans indicatif
  final immatCtrl  = TextEditingController();

  // --- Pays & indicatifs ------------------------------------------------------
  String _pays = 'Comores';
  String _dial = '+269'; // indicatif utilisé dans l’UI et à l’enregistrement

  // Tu peux étendre cette liste quand tu veux
  static const _countries = <Map<String, String>>[
    {'name':'Comores','dial':'+269'},
    {'name':'France','dial':'+33'},
    {'name':'Maroc','dial':'+212'},
    {'name':'Sénégal','dial':'+221'},
    {'name':"Côte d’Ivoire",'dial':'+225'},
    {'name':'Turquie','dial':'+90'},
    {'name':'Italie','dial':'+39'},
    {'name':'Allemagne','dial':'+49'},
    {'name':'Pologne','dial':'+48'},
    {'name':'États-Unis','dial':'+1'},
    {'name':'Autre…','dial':''},
  ];

  bool _loading = false;

  // Comores: 5–8 majuscules/chiffres/tirets (règle permissive)
  final _immatKm = RegExp(r'^[A-Z0-9-]{5,8}$');

  @override
  void dispose() {
    prenomCtrl.dispose();
    nomCtrl.dispose();
    telCtrl.dispose();
    immatCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---------------------------------------------------------------------------
  // Sélecteurs
  Future<void> _pickPaysEtIndicatif() async {
    final choice = await showModalBottomSheet<Map<String,String>>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        children: [
          for (final c in _countries)
            ListTile(
              title: Text(c['name']!),
              trailing: Text(c['dial']!.isEmpty ? '' : c['dial']!),
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
    if (choice != null) {
      setState(() {
        _pays = choice['name']!;
        _dial = choice['dial'] ?? '';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
    fillColor: const Color(0xFFF7F8FA),
  );

  // ---------------------------------------------------------------------------
  // Enregistrement via RPC
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final s = Supabase.instance.client;

    // compose le téléphone: indicatif + chiffres saisis (sans espaces)
    String? fullPhone;
    final raw = telCtrl.text.replaceAll(RegExp(r'\s'), '');
    if (raw.isNotEmpty) {
      fullPhone = _dial.isNotEmpty ? '$_dial$raw' : raw;
    }

    try {
      // UN SEUL appel: la fonction côté SQL s’occupe de profiles, user_roles,
      // chauffeurs et voitures.
      await s.rpc('setup_role', params: {
        'p_role'           : 'chauffeur',
        'p_prenom'         : prenomCtrl.text.trim(),
        'p_nom'            : nomCtrl.text.trim(),
        'p_telephone'      : fullPhone,
        'p_pays'           : _pays,
        'p_immatriculation': immatCtrl.text.trim().toUpperCase(),
      });

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/chauffeur', (_) => false);
    } on PostgrestException catch (e) {
      _snack('Erreur SQL: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil Chauffeur')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    if (isNarrow) ...[
                      TextFormField(
                        controller: prenomCtrl,
                        decoration: _deco('Prénom', Icons.badge),
                        validator: (v)=> (v==null||v.trim().isEmpty)?'Requis':null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nomCtrl,
                        decoration: _deco('Nom', Icons.badge_outlined),
                        validator: (v)=> (v==null||v.trim().isEmpty)?'Requis':null,
                      ),
                    ] else Row(children: [
                      Expanded(child: TextFormField(
                        controller: prenomCtrl,
                        decoration: _deco('Prénom', Icons.badge),
                        validator: (v)=> (v==null||v.trim().isEmpty)?'Requis':null,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(
                        controller: nomCtrl,
                        decoration: _deco('Nom', Icons.badge_outlined),
                        validator: (v)=> (v==null||v.trim().isEmpty)?'Requis':null,
                      )),
                    ]),
                    const SizedBox(height: 12),

                    // Téléphone avec country picker
                    Row(children: [
                      InkWell(
                        onTap: _pickPaysEtIndicatif,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.flag, size: 18),
                            const SizedBox(width: 6),
                            Text(_dial.isEmpty ? 'Code' : _dial,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const Icon(Icons.arrow_drop_down),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: telCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: _deco('Téléphone (optionnel)', Icons.phone)
                              .copyWith(prefixText: _dial.isEmpty ? '' : '$_dial '),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // Pays (affichage + changement via le même picker)
                    InkWell(
                      onTap: _pickPaysEtIndicatif,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: _deco('Pays', Icons.public),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(_pays, style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Immatriculation
                    TextFormField(
                      controller: immatCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _deco('Immatriculation', Icons.directions_car).copyWith(
                        helperText: _pays=='Comores'
                            ? 'Ex: 34AB73 (5–8 caractères majuscule/chiffre)'
                            : null,
                      ),
                      validator: (v) {
                        final t=(v??'').trim().toUpperCase();
                        if (t.isEmpty) return 'Requis';
                        if (_pays=='Comores' && !_immatKm.hasMatch(t)) return 'Format invalide';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity, height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _save,
                        icon: const Icon(Icons.check_circle),
                        label: _loading
                          ? const SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                          : const Text('Enregistrer et continuer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Annuler')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
