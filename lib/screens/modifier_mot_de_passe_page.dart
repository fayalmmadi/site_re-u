import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class ModifierMotDePassePage extends StatefulWidget {
  const ModifierMotDePassePage({super.key});

  @override
  State<ModifierMotDePassePage> createState() => _ModifierMotDePassePageState();
}

class _ModifierMotDePassePageState extends State<ModifierMotDePassePage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController oldPasswordController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool oldPasswordVisible = false;
  bool newPasswordVisible = false;
  bool confirmPasswordVisible = false;

  Future<void> changerMotDePasse() async {
    final oldPassword = oldPasswordController.text.trim();
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Les mots de passe ne correspondent pas')),
      );
      return;
    }

    try {
      // 🔐 Re-authentification nécessaire
      final email = Supabase.instance.client.auth.currentUser?.email;
      final session = await Supabase.instance.client.auth.signInWithPassword(
        email: email!,
        password: oldPassword,
      );

      if (session.user != null) {
        // ✅ Changement du mot de passe
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: newPassword),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Mot de passe mis à jour avec succès')),
        );

        Navigator.pop(context);
      } else {
        throw 'Ancien mot de passe incorrect';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4D3E),
        elevation: 0,
        title: const Text(
          'Suivi Taxi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
                Text(
                'change_password'.tr(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B4D3E),
                ),
              ),
              const SizedBox(height: 30),

              // 🔐 Ancien mot de passe
              TextFormField(
                controller: oldPasswordController,
                obscureText: !oldPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'old_password'.tr(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      oldPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        oldPasswordVisible = !oldPasswordVisible;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🔐 Nouveau mot de passe
              TextFormField(
                controller: newPasswordController,
                obscureText: !newPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'new_password'.tr(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      newPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        newPasswordVisible = !newPasswordVisible;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🔐 Confirmation
              TextFormField(
                controller: confirmPasswordController,
                obscureText: !confirmPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'confirm_password'.tr(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      confirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        confirmPasswordVisible = !confirmPasswordVisible;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    changerMotDePasse();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4D3E),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'save'.tr(),
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
