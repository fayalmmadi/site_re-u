import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Contrôle d’accès aux fonctionnalités limitées (ex: scan_qr, add_passenger)
/// via la fonction SQL `feature_gate_use`
///
/// ⚙️ Fonctionnement:
/// - Retourne true si l’action est autorisée
/// - Sinon, affiche un message et bloque le bouton
///
/// Exemple d’utilisation:
/// ```dart
/// final ok = await gateFeature(context, 'add_passenger');
/// if (!ok) return;
/// await ajouterPassager(1);
/// ```

final _supa = Supabase.instance.client;

Future<bool> gateFeature(BuildContext context, String feature) async {
  final uid = _supa.auth.currentUser?.id;
  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session expirée. Reconnecte-toi.')),
    );
    return false;
  }

  try {
    // 🔹 Appel de la fonction SQL feature_gate_use
    final dynamic raw = await _supa.rpc('feature_gate_use', params: {
      'p_user': uid,
      'p_feature': feature, // ex: 'add_passenger' | 'scan_qr'
    });

    // 🔹 Normaliser le résultat (peut être Map ou List selon SQL)
    Map<String, dynamic>? res;
    if (raw is Map<String, dynamic>) {
      res = raw;
    } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
      res = Map<String, dynamic>.from(raw.first as Map);
    }

    final allowed = res?['allowed'] == true;

    // ✅ Si autorisé, on laisse faire
    if (allowed) return true;

    // ⛔ Sinon, on récupère les infos de blocage
    final resetAtStr = res?['reset_at']?.toString();
    final DateTime? resetAt =
        resetAtStr != null ? DateTime.tryParse(resetAtStr) : null;

    final resetTxt = resetAt != null
        ? DateFormat('HH:mm').format(resetAt.toLocal())
        : 'plus tard';

    // 🔸 Boîte d’alerte utilisateur
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Abonnement requis'),
        content: Text(
          "Tu as atteint la limite de démo (3 essais / 2h) pour cette action.\n\n"
          "Réessaie après $resetTxt, ou active ton abonnement pour débloquer illimité.",
        ),
        actions: [
          TextButton(
            child: const Text('Plus tard'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.lock_open),
            label: const Text('Activer'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/abonnement');
            },
          ),
        ],
      ),
    );

    return false;
  } catch (e) {
    // ⚠️ En cas d’erreur, on laisse passer mais on avertit
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Contrôle abonnement indisponible: $e')),
    );
    return true;
  }
}
