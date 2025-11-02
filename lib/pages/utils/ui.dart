// lib/utils/ui.dart
import 'package:flutter/material.dart';

/// ---------- Contexte & responsive ----------

extension UiCtx on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  bool get isMobile => MediaQuery.of(this).size.width < 600;

  /// Padding horizontal cohérent (12 mobile, 24 desktop)
  EdgeInsets get sidePad =>
      EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24);

  /// Affiche rapidement un SnackBar (durée courte par défaut)
  void showSnack(String message, {Duration? duration}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(content: Text(message), duration: duration ?? const Duration(seconds: 2)),
    );
  }

  /// Affiche une erreur (snackbar rouge)
  void showError(Object err, {String prefix = 'Erreur:'}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text('$prefix $err'),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }
}

/// ---------- AppBars ----------

/// AppBar verte standardisée (comme ta “Demander une livraison”)
PreferredSizeWidget greenAppBar(
  BuildContext context, {
  required String title,
  bool showBack = true,
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: const Color(0xFF22C55E),
    title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    iconTheme: const IconThemeData(color: Colors.white),
    automaticallyImplyLeading: showBack,
    actions: actions,
  );
}

/// ---------- Dialogues ----------

/// Boite de confirmation simple. Renvoie true si confirmé.
Future<bool> confirm(
  BuildContext context, {
  String title = 'Confirmer',
  String message = 'Voulez-vous continuer ?',
  String cancelText = 'Annuler',
  String okText = 'Oui',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelText)),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(okText)),
      ],
    ),
  );
  return res == true;
}

/// Dialogue d’input simple (retourne le texte ou null)
Future<String?> prompt(
  BuildContext context, {
  String title = 'Saisir une valeur',
  String hint = '',
  String okText = 'Valider',
  String cancelText = 'Annuler',
  TextInputType keyboardType = TextInputType.text,
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String?>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        decoration: InputDecoration(hintText: hint),
        keyboardType: keyboardType,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(cancelText)),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(okText)),
      ],
    ),
  );
}

/// ---------- Overlays / loaders ----------

/// Affiche un overlay de chargement modal ; renvoie un disposer à appeler pour fermer.
VoidCallback showBlockingLoader(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(message ?? 'Chargement...'),
            ],
          ),
        ),
      ),
    ),
  );
  return () {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  };
}

/// ---------- Inputs helpers ----------

InputDecoration inputDec({
  String? label,
  String? hint,
  Widget? prefixIcon,
  String? prefixText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    prefixText: prefixText,
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
  );
}

/// Champ obligatoire : renvoie un message si vide.
String? requiredValidator(String? v, {String msg = 'Champ requis'}) {
  if (v == null || v.trim().isEmpty) return msg;
  return null;
}

/// Parse un nombre (virgule/point). Renvoie null si invalide.
double? parseNum(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(',', '.'));
}

/// ---------- Async setState safe ----------

/// Exécute une future puis appelle setState si le widget est encore monté.
/// Usage:
///   await setStateAsync(this, () async { ...; return () { ...state changes... }; });
Future<void> setStateAsync(State state, Future<VoidCallback?> Function() worker) async {
  final cb = await worker();
  if (state.mounted && cb != null) state.setState(cb);
}
