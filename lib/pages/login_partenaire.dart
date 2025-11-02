import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPartenairePage extends StatefulWidget {
  const LoginPartenairePage({Key? key}) : super(key: key);

  @override
  State<LoginPartenairePage> createState() => _LoginPartenairePageState();
}

class _LoginPartenairePageState extends State<LoginPartenairePage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscureText = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final auth = Supabase.instance.client.auth;
      final response = await auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user == null) {
        throw Exception("Connexion échouée");
      }

      // Vérifier validation partenaire
      final data = await Supabase.instance.client
          .from('partenaires')
          .select('est_valide')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data == null) {
        throw Exception("Compte partenaire introuvable.");
      }
      if (data['est_valide'] != true) {
        throw Exception("Votre compte n’a pas encore été validé par l’administrateur.");
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/partenaire_dashboard');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkGreen = const Color(0xFF1B4D3E);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480), // 👈 responsive Web/Mobile
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.green.shade600,
                        child: const Icon(Icons.handshake, size: 40, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Connexion Partenaire",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),

                      // Email
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: "Adresse e-mail",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return "Champ requis";
                          if (!v.contains('@')) return "Email invalide";
                          return null;
                        },
                        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 16),

                      // Mot de passe
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscureText,
                        decoration: InputDecoration(
                          labelText: "Mot de passe",
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscureText = !_obscureText),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        validator: (v) => (v == null || v.length < 6)
                            ? "Minimum 6 caractères"
                            : null,
                        onFieldSubmitted: (_) => _login(),
                      ),

                      // Lien mot de passe oublié
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/reset'),
                          child: const Text("Mot de passe oublié ?",
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Bouton connexion
                      _isLoading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: darkGreen,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text("Se connecter",
                                    style: TextStyle(fontSize: 18)),
                              ),
                            ),

                      const SizedBox(height: 16),

                      // 🔙 Bouton retour
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
            ),
          ),
        ),
      ),
    );
  }
}
