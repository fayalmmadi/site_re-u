// lib/flow/demande_livraison_flow.dart
import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/data/client_repository.dart';
import '../pages/demander_livraison_page.dart';

/// Lance le flux "Demander une livraison".
Future<void> startDemandeLivraisonFlow(BuildContext context) async {
  final repo = ClientRepository();
  Map<String, dynamic>? client = await repo.getFromCache();

  // Si aucun client -> on demande le profil d'abord
  if (client == null) {
    client = await _askClientProfile(context);
    if (client == null) return; // annulation
    await repo.saveIdToCache(client['id'] as String);
  }

  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DemanderLivraisonPage(client: client!)),
  );
}

/// Petite fiche de profil (pays + nom + téléphone). Minimaliste.
Future<Map<String, dynamic>?> _askClientProfile(BuildContext context) async {
  final supa = Supabase.instance.client;

  final nom = TextEditingController();
  final prenom = TextEditingController();
  final phone = TextEditingController();
  Country country = CountryParser.parseCountryCode('KM'); // Comores par défaut

  void _setPhonePrefix() {
    final prefix = '+${country.phoneCode} ';
    final local = phone.text.replaceFirst(RegExp(r'^\+\d+\s*'), '');
    phone.text = '$prefix$local';
    phone.selection = TextSelection.fromPosition(
      TextPosition(offset: phone.text.length),
    );
  }
  _setPhonePrefix();

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Créer votre profil client', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Pays'),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => showCountryPicker(
            context: ctx,
            showPhoneCode: true,
            onSelect: (c) {
              country = c;
              _setPhonePrefix();
              (ctx as Element).markNeedsBuild();
            },
          ),
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Row(children: [
              Text(country.flagEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text('${country.name} (+${country.phoneCode})')),
              const Icon(Icons.keyboard_arrow_down),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: prenom, decoration: const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              if (nom.text.trim().isEmpty || prenom.text.trim().isEmpty || phone.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nom, prénom et téléphone requis.')));
                return;
              }
              // insert client
              final row = await supa.from('clients').insert({
                'nom'        : nom.text.trim(),
                'prenom'     : prenom.text.trim(),
                'phone'      : phone.text.trim(),
                'pays'       : country.name,
                'country_iso': country.countryCode,
                'phone_code' : country.phoneCode,
              }).select().single();
              if (ctx.mounted) Navigator.pop(ctx, row);
            },
            child: const Text('Continuer'),
          ),
        )
      ]),
    ),
  );
}
