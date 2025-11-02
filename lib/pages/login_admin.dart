import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Change ceci si tu veux un autre mail admin autorisé
const String ADMIN_EMAIL = 'admin@tonapp.com';

class LoginAdminPage extends StatefulWidget {
  LoginAdminPage({super.key});

  @override
  State<LoginAdminPage> createState() => _LoginAdminPageState();
}

class _LoginAdminPageState extends State<LoginAdminPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: ADMIN_EMAIL); // pré-rempli
  final _password = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final auth = Supabase.instance.client.auth;
      final res = await auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      final user = res.user;
      if (user == null) {
        _showSnack("Connexion échouée");
        return;
      }

      // Autoriser seulement l'email admin
      final isAdmin = (user.email ?? '').toLowerCase() == ADMIN_EMAIL.toLowerCase();
      if (!isAdmin) {
        await auth.signOut();
        _showSnack("Accès admin requis");
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/admin_dashboard');
    } catch (e) {
      _showSnack("Erreur : $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final brand = const Color(0xFF118A8A);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420), // responsive Web/Mobile
              child: Column(
                children: [
                  // En-tête visuel
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [brand.withOpacity(.15), brand.withOpacity(.05)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.admin_panel_settings, size: 42, color: brand),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Espace Administrateur",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Connectez-vous pour gérer partenaires et clients",
                    style: TextStyle(color: Colors.black.withOpacity(.6)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Formulaire
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Adresse e-mail',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return "Champ requis";
                            if (!v.contains('@')) return "Email invalide";
                            return null;
                          },
                          onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.length < 6) ? "Minimum 6 caractères" : null,
                          onFieldSubmitted: (_) => _login(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            // ✅ utilise la route nommée -> pas besoin d'importer la page
                            onPressed: () => Navigator.pushNamed(context, '/reset'),
                            child: const Text('Mot de passe oublié ?'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _loading
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _login,
                                  icon: const Icon(Icons.login),
                                  label: const Text("Se connecter"),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    backgroundColor: brand,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, '/role-selection'),
                          child: const Text("← Retour au choix des rôles"),
                        ),
                      ],
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
}
