import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // <-- AJOUT
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupChauffeurPage extends StatefulWidget {
  const SignupChauffeurPage({super.key});

  @override
  State<SignupChauffeurPage> createState() => _SignupChauffeurPageState();
}

class _SignupChauffeurPageState extends State<SignupChauffeurPage> {
  final _formKey = GlobalKey<FormState>();

  final firstNameCtrl = TextEditingController();
  final lastNameCtrl  = TextEditingController();
  final emailCtrl     = TextEditingController();
  final passCtrl      = TextEditingController();
  final immatCtrl     = TextEditingController();

  bool loading = false;
  bool obscure = true;

  String _selectedCountry = 'France';
  final List<String> _countries = [
    'France','Turquie','Italie','Allemagne','Pologne','États-Unis',
    'Maroc','Sénégal','Côte d’Ivoire','Comores',
    'Autre pays…',
  ];

  final Map<String, RegExp> _strictPlateRegex = {
    'France'      : RegExp(r'^[A-Z]{2}-?\d{3}-?[A-Z]{2}$'),
    'Turquie'     : RegExp(r'^\d{2}\s?[A-Z]{1,3}\s?\d{2,4}$'),
    'Italie'      : RegExp(r'^[A-Z]{2}\d{3}[A-Z]{2}$'),
    'Allemagne'   : RegExp(r'^[A-ZÄÖÜ]{1,3}-[A-Z]{1,2}\s?\d{1,4}$'),
    'Pologne'     : RegExp(r'^[A-Z]{1,3}\s?\d[A-Z0-9]\s?\d{3,4}$'),
    'États-Unis'  : RegExp(r'^[A-Z0-9]{5,8}$'),
    'Maroc'       : RegExp(r'^\d{1,6}[-\s]?[A-Z\u0621-\u064A]{1,2}[-\s]?\d{1,2}$'),
    'Sénégal'     : RegExp(r'^[A-Z]{1,2}-\d{3,4}-[A-Z]{1,2}$'),
    'Côte d’Ivoire': RegExp(r'^\d{3,4}-[A-Z]{1,2}-\d{2}$'),
    'Comores'     : RegExp(r'^[A-Z0-9-]{5,8}$'),
  };

  final RegExp _permissive = RegExp(r'^[A-Z0-9-]{3,12}$');

  String? _validatePlate(String value, String country) {
    final v = value.trim().toUpperCase();
    if (v.isEmpty) return 'Immatriculation requise';
    if (_strictPlateRegex.containsKey(country)) {
      if (!_strictPlateRegex[country]!.hasMatch(v)) {
        return 'Format non valide pour $country';
      }
      return null;
    }
    if (!_permissive.hasMatch(v)) {
      return 'Format d’immatriculation invalide';
    }
    return null;
  }

  Future<void> _pickCountry() async {
    final ctrl = TextEditingController();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final mq = MediaQuery.of(context);
        return SizedBox(
          height: mq.size.height * 0.75,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setSt) {
                final q = ctrl.text.toLowerCase();
                final filtered = _countries.where((c) => c.toLowerCase().contains(q)).toList();
                return Column(
                  children: [
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Rechercher un pays…',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setSt(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => ListTile(
                          title: Text(filtered[i]),
                          onTap: () => Navigator.pop(context, filtered[i]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    if (choice != null) setState(() => _selectedCountry = choice);
  }

  // ----------------- INSCRIPTION -----------------
  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);
    try {
      final email = emailCtrl.text.trim();
      final password = passCtrl.text.trim();
      final supa = Supabase.instance.client;

      // URL de redirection pour le lien d’activation
      // -> marche en localhost ET en Netlify car on prend le domaine courant
      final redirectUrl = kIsWeb
          ? '${Uri.base.origin}/#/' // tu peux mettre une route dédiée ex: '#/auth-callback'
          : null;

      // 1) Crée l’utilisateur Auth
      final resp = await supa.auth.signUp(
        email: email,
        password: password,
        data: {
          'prenom'          : firstNameCtrl.text.trim(),
          'nom'             : lastNameCtrl.text.trim(),
          'role'            : 'chauffeur',
          'immatriculation' : immatCtrl.text.trim().toUpperCase(),
          'pays_immat'      : _selectedCountry,
        },
        // <-- AJOUT IMPORTANT POUR LE WEB
        emailRedirectTo: redirectUrl,
      );

      final user = resp.user;
      if (user == null) {
        throw const AuthException('Inscription échouée.');
      }

      // 2) Si email confirmation activée, pas de session pour le moment
      if (resp.session == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Compte créé. Vérifie ta boîte e-mail et clique sur le lien pour activer ton compte.",
            ),
          ),
        );
        return; // on n’insère pas en base tant que le compte n’est pas confirmé
      }

      // 3) Session présente => insert profile + voiture par défaut
      await supa.from('profiles').insert({
        'id'              : user.id,
        'prenom'          : firstNameCtrl.text.trim(),
        'nom'             : lastNameCtrl.text.trim(),
        'email'           : email,
        'role'            : 'chauffeur',
        'immatriculation' : immatCtrl.text.trim().toUpperCase(),
        'pays_immat'      : _selectedCountry,
      });

      await supa.from('voitures').insert({
        'owner_user_id'      : user.id,
        'immatriculation'    : immatCtrl.text.trim().toUpperCase(),
        'display_driver_name': firstNameCtrl.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Compte créé ! Tu peux te connecter.")),
      );
      Navigator.pop(context);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final already = msg.contains('already registered') || msg.contains('user already exists');
      final friendly = already ? 'Cet e-mail est déjà utilisé.' : e.message;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    immatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  // Bandeau
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.local_taxi, color: Colors.white, size: 46),
                        SizedBox(height: 10),
                        Text(
                          "Inscription",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Carte formulaire
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, spreadRadius: 2)],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (isNarrow) ...[
                            _textField(
                              controller: firstNameCtrl,
                              label: "Prénom",
                              icon: Icons.badge,
                              validator: (v) => (v == null || v.trim().isEmpty) ? "Prénom requis" : null,
                            ),
                            const SizedBox(height: 12),
                            _textField(
                              controller: lastNameCtrl,
                              label: "Nom",
                              icon: Icons.badge_outlined,
                              validator: (v) => (v == null || v.trim().isEmpty) ? "Nom requis" : null,
                            ),
                          ] else Row(
                            children: [
                              Expanded(
                                child: _textField(
                                  controller: firstNameCtrl,
                                  label: "Prénom",
                                  icon: Icons.badge,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? "Prénom requis" : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _textField(
                                  controller: lastNameCtrl,
                                  label: "Nom",
                                  icon: Icons.badge_outlined,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? "Nom requis" : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          _textField(
                            controller: emailCtrl,
                            label: "Email",
                            icon: Icons.email,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return "Email requis";
                              final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v);
                              return ok ? null : "Email invalide";
                            },
                          ),
                          const SizedBox(height: 12),

                          _textField(
                            controller: passCtrl,
                            label: "Mot de passe (min 6)",
                            icon: Icons.lock,
                            obscure: obscure,
                            suffix: IconButton(
                              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => obscure = !obscure),
                            ),
                            validator: (v) => (v == null || v.length < 6) ? "6 caractères minimum" : null,
                          ),
                          const SizedBox(height: 12),

                          if (isNarrow) ...[
                            _countryPickerTile(),
                            const SizedBox(height: 12),
                            _immatField(),
                          ] else Row(
                            children: [
                              Expanded(child: _countryPickerTile()),
                              const SizedBox(width: 12),
                              Expanded(child: _immatField()),
                            ],
                          ),

                          const SizedBox(height: 18),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: loading ? null : _signup,
                              icon: const Icon(Icons.check_circle),
                              label: loading
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 6),
                                      child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                    )
                                  : const Text("Créer mon compte"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF22C55E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("← Retour"),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------- Widgets réutilisables
  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
      ),
    );
  }

  Widget _countryPickerTile() {
    return InkWell(
      onTap: _pickCountry,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Pays',
          prefixIcon: const Icon(Icons.flag),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFFF7F8FA),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(_selectedCountry, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget _immatField() {
    return TextFormField(
      controller: immatCtrl,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'Immatriculation',
        prefixIcon: const Icon(Icons.directions_car),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        helperText: _strictPlateRegex.containsKey(_selectedCountry)
            ? 'Format contrôlé pour $_selectedCountry'
            : 'Format non vérifié (pays permissif)',
      ),
      validator: (v) => _validatePlate(v ?? '', _selectedCountry),
    );
  }
}
