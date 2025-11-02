import 'package:flutter/material.dart';
import '../utils/currency.dart';

import '../reviews_page.dart';
import './avg_stars_badge.dart';
import './mini_thumbs.dart';
import './gallery.dart';
import './demande_livraison_modal.dart';

class CourierCard extends StatelessWidget {
  const CourierCard({
    super.key,
    required this.livreur,
    required this.onAfterRequest,
    required this.onEnsureClient,
    this.clientCountryIso,
    this.clientCurrencyCode,
    this.clientCurrencySymbol,
  });

  final Map<String, dynamic> livreur;
  final Future<void> Function()? onAfterRequest;
  final Future<Map<String, dynamic>> Function({String? prefillPhone}) onEnsureClient;

  // 👇 nouveaux paramètres optionnels venant du client
  final String? clientCountryIso;
  final String? clientCurrencyCode;
  final String? clientCurrencySymbol;

  /// ────────────────────────────────────────────────
  /// Helpers devise dynamique selon le pays du client
  /// ────────────────────────────────────────────────
  String _symbolForCountry(String? iso) {
    switch (iso?.toUpperCase()) {
      case 'KM':
        return 'CF'; // Comores
      case 'MG':
        return 'Ar'; // Madagascar
      case 'SN':
      case 'BJ':
      case 'CI':
      case 'TG':
      case 'BF':
      case 'NE':
      case 'ML':
        return 'CFA'; // Afrique Ouest
      case 'CM':
      case 'GA':
      case 'CG':
      case 'GQ':
      case 'TD':
      case 'CF':
        return 'FCFA'; // Afrique Centrale
      case 'US':
        return r'$';
      case 'FR':
        return '€';
      default:
        return '€';
    }
  }

  String _symbolForCode(String? code) {
    switch (code?.toUpperCase()) {
      case 'KMF':
        return 'CF';
      case 'MGA':
        return 'Ar';
      case 'XOF':
        return 'CFA';
      case 'XAF':
        return 'FCFA';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      default:
        return '€';
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = '${livreur['id'] ?? livreur['livreur_id']}';
    final nom = (livreur['nom'] ?? 'Livreur').toString();
    final type = (livreur['type_livraison'] ?? 'Livraison tout type').toString();
    final zones = (livreur['zones'] ?? '').toString();

    final price = (livreur['price_amount'] as num?)?.toDouble();
    final cur = (livreur['price_currency'] as String?) ?? 'EUR';
    final nego = (livreur['negociable'] == true);

    final photo1 = (livreur['photo1'] ?? '').toString();
    final photo2 = (livreur['photo2'] ?? '').toString();
    final images = [photo1, photo2].where((u) => u.isNotEmpty).toList();

    // 🔹 Sélection automatique de la devise selon le client
    final dynamicSymbol = clientCurrencySymbol ??
        _symbolForCode(clientCurrencyCode ?? cur) ??
        _symbolForCountry(clientCountryIso);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MiniThumbs(images: images, onTap: () => _openGallery(context, images)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      AvgStarsBadge(livreurId: id, showProWhenHigh: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(type, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.map_outlined, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          zones.isEmpty ? 'Zones : —' : 'Zones : $zones',
                          style: const TextStyle(color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (price != null && price > 0)
                        Row(
                          children: [
                            Text(
                              '$dynamicSymbol ${price.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (nego ? Colors.orange : Colors.green).withOpacity(.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(nego ? 'À négocier' : 'Prix fixe'),
                            ),
                          ],
                        )
                      else
                        const Text('À négocier', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReviewsPage(livreurId: id, livreurName: nom),
                            ),
                          );
                        },
                        child: const Text('Voir avis'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.black,
                        ),
                        // ✅ ici on transmet les infos du client à la fenêtre modal
                        onPressed: () => showDemandeLivraisonModal(
                          context: context,
                          livreur: livreur,
                          onEnsureClient: onEnsureClient,
                          onAfterRequest: onAfterRequest,
                          clientCountryIso: clientCountryIso,
                          clientCurrencyCode: clientCurrencyCode,
                          clientCurrencySymbol: clientCurrencySymbol,
                        ),
                        child: const Text('Choisir', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGallery(BuildContext context, List<String> images) {
    if (images.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: AspectRatio(aspectRatio: 4 / 3, child: Gallery(images: images)),
      ),
    );
  }
}
