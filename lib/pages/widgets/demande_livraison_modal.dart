import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/currency.dart';

Future<void> showDemandeLivraisonModal({
  required BuildContext context,
  required Map<String, dynamic> livreur,
  required Future<Map<String, dynamic>> Function({String? prefillPhone}) onEnsureClient,
  Future<void> Function()? onAfterRequest,
  String? clientCountryIso,
  String? clientCurrencyCode,
  String? clientCurrencySymbol,
}) async {
  final prixCtrl  = TextEditingController(text: (livreur['price_amount'] as num?)?.toString() ?? '');
  final depCtrl   = TextEditingController();
  final arrCtrl   = TextEditingController();
  final phoneCtrl = TextEditingController();

  const objets = <String>[
    'Colis', 'Sac', 'Livres', 'Meubles', 'Matériaux', 'Briques',
    'Électroménager', 'Courses', 'Documents', 'Vêtements', 'Aliments',
    'Autre (préciser)',
  ];
  String? objetChoice;
  final objetAutreCtrl = TextEditingController();

  final client = await onEnsureClient();
  final String clientCountry = (client['pays'] ?? livreur['pays'] ?? 'France').toString();

  // ✅ Détermination intelligente de la devise
  String currencyCode = clientCurrencyCode ?? countryToCurrency(clientCountry);
  String symbol = clientCurrencySymbol ??
      _resolveSymbol(iso: clientCountryIso ?? '', code: currencyCode);

  final bool negociable = (livreur['negociable'] == true);
  final String? driverCur = (livreur['price_currency'] as String?);
  if (!negociable && driverCur != null && driverCur.isNotEmpty) {
    currencyCode = driverCur;
    symbol = _symbolForCode(driverCur);
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final price = (livreur['price_amount'] as num?)?.toDouble();

      String buildObjet() {
        if (objetChoice == null) return '';
        if (objetChoice == 'Autre (préciser)') {
          final t = objetAutreCtrl.text.trim();
          return t.isEmpty ? 'Autre' : t;
        }
        return objetChoice!;
      }

      double parsePrix(String raw) {
        final cleaned = raw.replaceAll(RegExp(r'[^0-9\.,]'), '');
        return double.tryParse(cleaned.replaceAll(',', '.')) ?? 0;
      }

      return Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Bandeau prix
              Row(
                children: [
                  if (price != null && price > 0)
                    Text(
                      '$symbol ${price.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (negociable ? Colors.orange : Colors.green).withOpacity(.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(negociable ? 'À négocier' : 'Prix fixe'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: objetChoice,
                items: objets.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) {
                  objetChoice = v;
                  (ctx as Element).markNeedsBuild();
                },
                decoration: const InputDecoration(
                  labelText: 'Objet à transporter',
                  border: OutlineInputBorder(),
                ),
              ),
              if (objetChoice == 'Autre (préciser)') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: objetAutreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Préciser l’objet',
                    hintText: 'ex: tableau, ordinateur…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 8),

              TextFormField(
                readOnly: true,
                initialValue: clientCountry,
                decoration: const InputDecoration(
                  labelText: 'Pays',
                  prefixIcon: Icon(Icons.public),
                  helperText: 'Le pays vient de votre profil et filtre les livreurs',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: depCtrl,
                decoration: const InputDecoration(
                  labelText: 'Adresse de départ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: arrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Adresse d’arrivée',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: prixCtrl,
                enabled: negociable,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Prix proposé',
                  prefixText: '$symbol ',
                  helperText: negociable
                      ? 'Vous pouvez proposer un autre prix'
                      : 'Prix fixé par le livreur',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone client',
                  helperText: 'Masqué au livreur jusqu’à acceptation (vide = n° du profil)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final depart = depCtrl.text.trim();
                    final arrivee = arrCtrl.text.trim();
                    final objet = buildObjet();
                    final prixNum = negociable
                        ? parsePrix(prixCtrl.text)
                        : ((livreur['price_amount'] as num?)?.toDouble() ?? 0);
                    final phone = phoneCtrl.text.trim();

                    if (depart.isEmpty || arrivee.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Départ et arrivée requis.')),
                      );
                      return;
                    }
                    if (objet.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Choisissez ou précisez l’objet.')),
                      );
                      return;
                    }

                    final supa = Supabase.instance.client;
                    await supa.from('livraison_demandes').insert({
                      'client_id': client['id'],
                      'livreur_id': '${livreur['id'] ?? livreur['livreur_id']}',
                      'depart_adresse': depart,
                      'arrivee_adresse': arrivee,
                      'prix_propose': prixNum,
                      'devise': currencyCode,
                      'objet': objet,
                      'status': 'pending',
                      'client_phone': phone.isEmpty ? client['phone'] : phone,
                      'client_pays': clientCountry,
                      'client_nom': '${client['prenom'] ?? ''} ${client['nom'] ?? ''}'.trim(),
                    });

                    if (onAfterRequest != null) await onAfterRequest!();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Demande envoyée ✅')),
                      );
                    }
                  },
                  child: const Text('Envoyer la demande'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────
// Helpers pour les symboles de devises
// ─────────────────────────────────────────────
String _resolveSymbol({String? iso, String? code}) {
  if (iso != null && iso.isNotEmpty) {
    final s = _symbolForCountry(iso);
    if (s != '€' || (code ?? '').toUpperCase() == 'EUR') return s;
  }
  if (code != null && code.isNotEmpty) {
    return _symbolForCode(code);
  }
  return '€';
}

String _symbolForCountry(String iso) {
  switch (iso.toUpperCase()) {
    case 'KM': return 'CF';
    case 'MG': return 'Ar';
    case 'SN':
    case 'BJ':
    case 'CI':
    case 'TG':
    case 'BF':
    case 'NE':
    case 'ML': return 'CFA';
    case 'CM':
    case 'GA':
    case 'CG':
    case 'GQ':
    case 'TD':
    case 'CF': return 'FCFA';
    case 'US': return r'$';
    case 'FR': return '€';
    default: return '€';
  }
}

String _symbolForCode(String code) {
  switch (code.toUpperCase()) {
    case 'KMF': return 'CF';
    case 'MGA': return 'Ar';
    case 'XOF': return 'CFA';
    case 'XAF': return 'FCFA';
    case 'USD': return r'$';
    case 'EUR': return '€';
    default: return '€';
  }
}
