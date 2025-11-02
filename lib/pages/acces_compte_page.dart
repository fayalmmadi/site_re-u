import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccesComptePage extends StatefulWidget {
  const AccesComptePage({super.key});

  @override
  State<AccesComptePage> createState() => _AccesComptePageState();
}

class _AccesComptePageState extends State<AccesComptePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // --- Login ---
  final _loginKey = GlobalKey<FormState>();
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  bool _loginObscure = true;
  bool _loginLoading = false;

  // --- Signup ---
  final _signupKey = GlobalKey<FormState>();
  final _signupEmail = TextEditingController();
  final _signupPass = TextEditingController();
  bool _signupObscure = true;
  bool _signupLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmail.dispose();
    _loginPass.dispose();
    _signupEmail.dispose();
    _signupPass.dispose();
    super.dispose();
  }

  // -------------------------------------------------
  // NAVIGATION
  // -------------------------------------------------
  Future<void> _goToRoles() async {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/roles', (_) => false);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------------------------------------
  // ACTIONS
  // -------------------------------------------------
  Future<void> _doLogin() async {
    if (!_loginKey.currentState!.validate()) return;
    setState(() => _loginLoading = true);
    try {
      final supa = Supabase.instance.client;
      final res = await supa.auth.signInWithPassword(
        email: _loginEmail.text.trim(),
        password: _loginPass.text.trim(),
      );

      if (res.user != null) {
        await _goToRoles();
      } else {
        _snack("Connexion échouée. Vérifie tes identifiants.");
      }
    } catch (e) {
      _snack("Erreur de connexion : $e");
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  Future<void> _doSignup() async {
    if (!_signupKey.currentState!.validate()) return;
    setState(() => _signupLoading = true);
    try {
      final supa = Supabase.instance.client;
      final res = await supa.auth.signUp(
        email: _signupEmail.text.trim(),
        password: _signupPass.text.trim(),
      );

      // Si la confirmation e-mail est désactivée, session dispo ⇒ on va aux rôles
      if (res.session != null) {
        await _goToRoles();
        return;
      }

      // Si la confirmation est activée, prévenir l’utilisateur :
      _snack("Inscription réussie. Vérifie ta boîte mail pour confirmer ton compte.");
      // Tu peux rediriger vers une page d’info si tu en as une :
      // Navigator.pushReplacementNamed(context, '/email-confirmed');
    } catch (e) {
      _snack("Erreur d'inscription : $e");
    } finally {
      if (mounted) setState(() => _signupLoading = false);
    }
  }

  // -------------------------------------------------
  // UI
  // -------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accéder à mon espace'),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fond léger
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF6F8FB), Color(0xFFE9F3EE)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // En-tête
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withOpacity(.09),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: const Color(0xFF22C55E),
                                child: const Icon(Icons.lock, color: Colors.white, size: 28),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Espace sécurisé",
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Connecte-toi ou crée ton compte, puis choisis ton rôle.",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Onglets
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TabBar(
                            controller: _tabs,
                            indicator: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.black87,
                            tabs: const [
                              Tab(text: 'Se connecter'),
                              Tab(text: 'Créer un compte'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        SizedBox(
                          height: 280,
                          child: TabBarView(
                            controller: _tabs,
                            children: [
                              // ---------------------- LOGIN ----------------------
                              Form(
                                key: _loginKey,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _loginEmail,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: 'Adresse e-mail',
                                        prefixIcon: Icon(Icons.email_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Entrez votre e-mail';
                                        }
                                        if (!v.contains('@')) {
                                          return 'E-mail invalide';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _loginPass,
                                      obscureText: _loginObscure,
                                      decoration: InputDecoration(
                                        labelText: 'Mot de passe',
                                        prefixIcon: const Icon(Icons.lock_outline),
                                        border: const OutlineInputBorder(),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(() => _loginObscure = !_loginObscure),
                                          icon: Icon(_loginObscure ? Icons.visibility : Icons.visibility_off),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Entrez votre mot de passe';
                                        }
                                        if (v.length < 6) {
                                          return 'Au moins 6 caractères';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton.icon(
                                        onPressed: _loginLoading ? null : _doLogin,
                                        icon: const Icon(Icons.login),
                                        label: _loginLoading
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Text('Se connecter'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF22C55E),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => Navigator.pushNamed(context, '/reset'),
                                      child: const Text('Mot de passe oublié ?'),
                                    ),
                                  ],
                                ),
                              ),

                              // ---------------------- SIGNUP ----------------------
                              Form(
                                key: _signupKey,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _signupEmail,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: 'Adresse e-mail',
                                        prefixIcon: Icon(Icons.email_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Entrez votre e-mail';
                                        }
                                        if (!v.contains('@')) {
                                          return 'E-mail invalide';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _signupPass,
                                      obscureText: _signupObscure,
                                      decoration: InputDecoration(
                                        labelText: 'Choisir un mot de passe',
                                        prefixIcon: const Icon(Icons.lock_outline),
                                        border: const OutlineInputBorder(),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(() => _signupObscure = !_signupObscure),
                                          icon: Icon(_signupObscure ? Icons.visibility : Icons.visibility_off),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Choisissez un mot de passe';
                                        }
                                        if (v.length < 6) {
                                          return 'Au moins 6 caractères';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton.icon(
                                        onPressed: _signupLoading ? null : _doSignup,
                                        icon: const Icon(Icons.person_add_alt_1),
                                        label: _signupLoading
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Text('Créer mon compte'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1D4ED8),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "En créant un compte, vous serez redirigé(e) vers l’écran des rôles.",
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Retour à l’accueil'),
                        ),
                      ],
                    ),
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
