import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

import 'driver_dashboard.dart';
import 'payment_selection_page.dart';

class AbonnementPage extends StatefulWidget {
  const AbonnementPage({Key? key}) : super(key: key);

  @override
  State<AbonnementPage> createState() => _AbonnementPageState();
}

class _AbonnementPageState extends State<AbonnementPage> {
  final supa = Supabase.instance.client;

  bool isAnnuel = false;
  int montantAbonnement = 0;
  int nbVoitures = 0;

  bool _loading = true;
  bool _redeeming = false;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      await _calculerMontant();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Détecte la colonne propriétaire dans `voitures`.
  Future<int> _fetchCarCountSmart(String uid) async {
    final table = supa.from('voitures');

    try {
      final res = await table.select('id').eq('user_id', uid);
      if (res is List) return res.length;
    } catch (_) {}

    try {
      final res = await table.select('id').eq('owner_user_id', uid);
      if (res is List) return res.length;
    } catch (_) {}

    try {
      final res = await table.select('id').eq('proprietaire_id', uid);
      if (res is List) return res.length;
    } catch (_) {}

    try {
      final res = await table.select('id').eq('chauffeur_user_id', uid);
      if (res is List) return res.length;
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Impossible de déterminer la colonne propriétaire dans 'voitures'. Vérifie (user_id/owner_user_id/proprietaire_id...).",
          ),
        ),
      );
    }
    return 0;
  }

  Future<void> _calculerMontant() async {
    final user = supa.auth.currentUser;
    if (user == null) return;

    final count = await _fetchCarCountSmart(user.id);
    setState(() {
      final unit = isAnnuel ? 114 : 10; // tes tarifs
      final effectiveCars = (count <= 0) ? 1 : count; // au moins 1 voiture
      nbVoitures = effectiveCars;
      montantAbonnement = effectiveCars * unit;
    });
  }

  DateTime get _prochainPrelevement {
    final now = DateTime.now();
    final month = now.month + (isAnnuel ? 0 : 1);
    final year = now.year + (isAnnuel ? 1 : (month > 12 ? 1 : 0));
    final fixedMonth = isAnnuel ? now.month : (month > 12 ? 1 : month);
    return DateTime(year, fixedMonth, now.day);
  }

  String get _dateFormat {
    try {
      return DateFormat('d MMM y', 'fr_FR').format(_prochainPrelevement);
    } catch (_) {
      final m = {
        1: 'janv.', 2: 'févr.', 3: 'mars', 4: 'avr.', 5: 'mai', 6: 'juin',
        7: 'juil.', 8: 'août', 9: 'sept.', 10: 'oct.', 11: 'nov.', 12: 'déc.',
      };
      final d = _prochainPrelevement;
      return '${d.day} ${m[d.month]} ${d.year}';
    }
  }

  String _fmtMoney(num x) {
    try {
      return NumberFormat.simpleCurrency(name: 'EUR').format(x);
    } catch (_) {
      return '${x.toStringAsFixed(2)} €';
    }
  }

  /// ✅ Valide un code partenaire via RPC SECURITY DEFINER.
  ///     RPC attend: redeem_taxi_subscription_code(p_user uuid, p_code text)
  /// La RPC doit:
  ///   - vérifier le code,
  ///   - calculer valid_until,
  ///   - faire UPSERT dans public.subscriptions (clé = user_id),
  ///   - marquer le code utilisé.
  Future<void> _validerCodePartenaire(String raw) async {
  final user = supa.auth.currentUser;
  if (user == null) return;

  final code = raw.trim().toUpperCase();
  if (code.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entre ton code partenaire')),
    );
    return;
  }

  setState(() => _redeeming = true);
  try {
    final res = await supa.rpc('redeem_taxi_subscription_code', params: {
      'p_user': user.id,
      'p_code': code,
    });

    print('Réponse RPC Supabase: $res');

    // Supabase peut renvoyer Map OU List<Map>
    Map<String, dynamic>? row;
    if (res is List && res.isNotEmpty) {
      row = Map<String, dynamic>.from(res.first);
    } else if (res is Map) {
      row = Map<String, dynamic>.from(res);
    }

    if (row == null || row['ok'] != true) {
      throw row?['error']?.toString() ?? 'Code invalide ou expiré.';
    }

    final amount = (row['amount'] as num?) ?? 0;
    final cars   = (row['cars'] as int?) ?? 0;
    final period = (row['period']?.toString() ?? 'mensuel');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Code validé : ${_fmtMoney(amount)} pour $cars voiture(s) (${period == 'annuel' ? 'annuel' : 'mensuel'}).')),
    );

    _codeCtrl.clear();

    // Reviens au dashboard (le bandeau relira subscriptions)
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverDashboard()),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  } finally {
    if (mounted) setState(() => _redeeming = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final darkGreen = const Color(0xFF004D40);
    final borderRadiusTop = const BorderRadius.vertical(top: Radius.circular(32));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: darkGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DriverDashboard()),
            );
          },
        ),
        elevation: 0,
        title: Text('subscription'.tr(), style: const TextStyle(color: Colors.white)),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final vh = constraints.maxHeight;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 360,
                        minHeight: vh - 32,
                      ),
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
                        elevation: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: darkGreen,
                                borderRadius: borderRadiusTop,
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.directions_car, color: Colors.white, size: 40),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'ABONNEMENT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Prix dynamique
                            Text(
                              isAnnuel
                                  ? '${_fmtMoney(montantAbonnement)}/an'
                                  : '${_fmtMoney(montantAbonnement)}/mois',
                              style: TextStyle(fontSize: 28, color: darkGreen, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '(${nbVoitures} voiture(s) × ${_fmtMoney(isAnnuel ? 114 : 10)}${isAnnuel ? '/an' : '/mois'})',
                              style: const TextStyle(color: Colors.black54),
                            ),

                            const SizedBox(height: 16),

                            // Switch mensuel/annuel
                            Container(
                              width: 240,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: darkGreen),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        if (!isAnnuel) return;
                                        setState(() => isAnnuel = false);
                                        await _calculerMontant();
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: !isAnnuel ? darkGreen : Colors.transparent,
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          'Mensuel',
                                          style: TextStyle(
                                            color: !isAnnuel ? Colors.white : darkGreen,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        if (isAnnuel) return;
                                        setState(() => isAnnuel = true);
                                        await _calculerMontant();
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isAnnuel ? darkGreen : Colors.transparent,
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          'Annuel',
                                          style: TextStyle(
                                            color: isAnnuel ? Colors.white : darkGreen,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Avantages + échéance
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle, color: darkGreen),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('QR code intelligent pour $nbVoitures voiture(s)')),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle, color: darkGreen),
                                      const SizedBox(width: 10),
                                      const Expanded(child: Text('Accès à Suivi Taxi')),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(Icons.credit_card, color: darkGreen),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Prochain prélèvement :\n$_dateFormat',
                                          style: const TextStyle(height: 1.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Code partenaire (espèces)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _codeCtrl,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        labelText: 'Code partenaire (espèces)',
                                        hintText: 'Ex: 6GE7T547',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _redeeming
                                        ? null
                                        : () => _validerCodePartenaire(_codeCtrl.text),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: darkGreen,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: _redeeming
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Valider'),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Paiement en ligne
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                children: [
                                  ElevatedButton(
                                    onPressed: (montantAbonnement <= 0)
                                        ? null
                                        : () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PaymentSelectionPage(
                                                  amount: montantAbonnement.toDouble(),
                                                  isAnnual: isAnnuel,
                                                ),
                                              ),
                                            );
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: darkGreen,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(double.infinity, 48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                    ),
                                    child: const Text('Choisir'),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: () {
                                      // TODO: résiliation / pause si besoin
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: darkGreen,
                                      side: BorderSide(color: darkGreen),
                                      minimumSize: const Size(double.infinity, 48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                    ),
                                    child: const Text('Résilier'),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
