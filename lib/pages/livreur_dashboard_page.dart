import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'livreur_profile_edit_page.dart';
import 'livreur_demandes_page.dart';
import 'mes_vehicules_page.dart';

// GPS
import 'package:geolocator/geolocator.dart';

class LivreurDashboardPage extends StatefulWidget {
  const LivreurDashboardPage({super.key});

  @override
  State<LivreurDashboardPage> createState() => _LivreurDashboardPageState();
}

class _LivreurDashboardPageState extends State<LivreurDashboardPage> {
  final supabase = Supabase.instance.client;

  // Données
  Map<String, dynamic>? _profil;
  double _walletBalance = 0;
  String _walletCurrency = 'EUR';
  double _capAmount = 5;
  int _pendingCount = 0;

  // Stats mois
  int _monthDeliveries = 0;
  double _monthGross = 0;       // revenus bruts
  double _monthCommission = 0;  // estimation 10%

  bool _loading = true;

  // Taux affiché (texte “Taux du solde: 10%”)
  static const double _walletCommissionRateDisplay = 0.10;

  // Realtime
  late RealtimeChannel _walletChan;

  // ------- Bloqué quand le solde atteint l’objectif -------
  bool get _isBlocked => _walletBalance >= _capAmount - 1e-6;

  // ========= MAPPINGS (devise à partir de l’ISO-2 du pays) =========
  static const Map<String, String> _isoToCurrency = {
    // Afrique
    'KM': 'KMF', 'MG': 'MGA', 'SN': 'XOF', 'CM': 'XAF', 'CI': 'XOF',
    'MA': 'MAD', 'TN': 'TND', 'KE': 'KES', 'NG': 'NGN', 'ZA': 'ZAR', 'ET': 'ETB',
    'DZ': 'DZD', 'EG': 'EGP',
    // Europe
    'FR': 'EUR', 'BE': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'DE': 'EUR', 'PT': 'EUR',
    'IE': 'EUR', 'GB': 'GBP', 'CH': 'CHF', 'PL': 'PLN', 'RO': 'RON', 'SE': 'SEK',
    'NO': 'NOK',
    // Amériques
    'US': 'USD', 'CA': 'CAD', 'BR': 'BRL', 'MX': 'MXN', 'AR': 'ARS',
    // Asie / Océanie (échantillon)
    'IN': 'INR', 'CN': 'CNY', 'JP': 'JPY', 'AE': 'AED', 'SA': 'SAR', 'ID': 'IDR',
    'AU': 'AUD',
  };

  String _currencyForProfile(Map<String, dynamic>? p) {
    // 1) priorité à la devise déjà stockée par profil_livreur_page.dart
    final fromProfile = (p?['currency_code'] as String?);
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;

    // 2) fallback via country_iso
    final iso = (p?['country_iso'] as String?)?.toUpperCase();
    if (iso != null && _isoToCurrency.containsKey(iso)) return _isoToCurrency[iso]!;

    // 3) dernier recours
    return 'EUR';
  }

  // ============ GPS temps réel ============
  Timer? _gpsTimer;
  bool _shareLive = false;
  DateTime? _lastGpsAt;

  @override
  void initState() {
    super.initState();

    _loadAll().then((_) {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;

      // Nettoie une éventuelle ancienne souscription
      try { _walletChan.unsubscribe(); } catch (_) {}

      // 1️⃣ Crée le canal
_walletChan = Supabase.instance.client.channel('public:commission_wallets');

// 2️⃣ Écoute les changements Postgres (UPDATE sur le wallet du livreur)
_walletChan.onPostgresChanges(
  event: PostgresChangeEvent.update,
  schema: 'public',
  table: 'commission_wallets',
  filter: PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'user_id',
    value: uid,
  ),
  callback: (payload) {
    _onWalletUpdate(payload);
  },
);

// 3️⃣ S’abonne
_walletChan.subscribe();

    });
  }

  @override
  void dispose() {
    try { _walletChan.unsubscribe(); } catch (_) {}
    _gpsTimer?.cancel(); // stop GPS timer
    super.dispose();
  }

  // ========= Utils =========

  String _fmtMoney(String code, num amount, {int? digits}) {
    try {
      final f = NumberFormat.simpleCurrency(
        name: code,
        decimalDigits: digits ?? (amount % 1 == 0 ? 0 : 2),
      );
      final s = f.format(amount);
      return s.trim().isEmpty ? '$code ${amount.toStringAsFixed(digits ?? 0)}' : s;
    } catch (_) {
      return '$code ${amount.toStringAsFixed(digits ?? 0)}';
    }
  }

  T? _as<T>(dynamic v) => v is T ? v : null;

  // ========= Wallet (user_id only) =========

  Future<Map<String, dynamic>?> _getWalletByUser(String uid) async {
    final w = await supabase
        .from('commission_wallets')
        .select('balance, currency_code, cap_amount')
        .eq('user_id', uid)
        .maybeSingle() as Map<String, dynamic>?;
    return w;
  }

  Future<void> _ensureWalletDefaults(String uid, {String currency = 'EUR', double cap = 5}) async {
    await supabase.rpc('set_wallet_params', params: {
      'p_user': uid,
      'p_currency': currency,
      'p_cap': cap,
    });
  }

  // ========= Load =========

  Future<void> _loadAll() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.rpc('ensure_livreur_profile');

      // 1) Profil livreur
      final p = await supabase
          .from('livreurs')
          .select()
          .eq('user_id', uid)
          .maybeSingle() as Map<String, dynamic>?;

      // 2) Wallet par user_id (avec création si absent) — devise fiable depuis le profil
      var w = await _getWalletByUser(uid);
      final countryIso = (p?['country_iso'] as String?) ?? 'FR'; // fallback

      // Aligne toujours (créera ou mettra à jour sans toucher au solde)
      await supabase.rpc('set_wallet_from_country', params: {
        'p_user': uid,
        'p_country_iso': countryIso,
      });

      w = await _getWalletByUser(uid);

      final currency = _as<String>(w?['currency_code']) ?? _currencyForProfile(p);
      final cap      = (_as<num>(w?['cap_amount'])?.toDouble()) ?? 5.0;
      final balance  = (_as<num>(w?['balance'])?.toDouble()) ?? 0.0;

      // 3) Demandes pending (liées à CE livreur)
      int pendingCount = 0;
      if (p?['id'] != null) {
        final pending = await supabase
            .from('livraison_demandes')
            .select('id')
            .eq('livreur_id', p!['id'])
            .eq('status', 'pending');
        if (pending is List) pendingCount = pending.length;
      }

      // 4) Stats mensuelles (vue)
      int deliveries = 0;
      double gross = 0.0;
      double appCommission = 0.0;

      final statsRow = await supabase
          .from('v_livreur_stats_month')
          .select('deliveries_count, gross_revenue, app_commission')
          .eq('user_id', uid)
          .maybeSingle() as Map<String, dynamic>?;

      if (statsRow != null) {
        deliveries = (statsRow['deliveries_count'] as int?) ?? 0;
        gross = (statsRow['gross_revenue'] as num?)?.toDouble() ?? 0.0;
        appCommission = (statsRow['app_commission'] as num?)?.toDouble() ?? (gross * 0.10);
      }

      if (!mounted) return;
      setState(() {
        _profil = p;
        _walletBalance = balance;
        _walletCurrency = currency;
        _capAmount = cap;
        _pendingCount = pendingCount;
        _monthDeliveries = deliveries;
        _monthGross = gross;
        _monthCommission = double.parse(appCommission.toStringAsFixed(2));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement: $e')),
      );
    }
  }

  // ========= Realtime callback =========

  void _onWalletUpdate(dynamic payload, [dynamic _ref]) {
    final map = payload as Map<String, dynamic>;
    final row = map['new'] as Map<String, dynamic>?;
    if (row == null || !mounted) return;

    setState(() {
      _walletBalance  = (row['balance'] as num?)?.toDouble() ?? _walletBalance;
      _walletCurrency = (row['currency_code'] as String?) ?? _walletCurrency;
      _capAmount      = (row['cap_amount'] as num?)?.toDouble() ?? _capAmount;
    });
  }

  // ========= Navigation =========

  void _goBackToRoles() => Navigator.pushReplacementNamed(context, '/roles');

  Future<void> _openDemandes() async {
    final livreurId = _profil?['id'] as String?;
    if (livreurId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID livreur introuvable')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LivreurDemandesPage(livreurId: livreurId)),
    );
    if (changed == true) {
      await _loadAll();
    }
  }

  Future<void> _openEditProfile() async {
    final id = _profil?['id'] as String?;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID livreur introuvable')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LivreurProfileEditPage(livreurId: id)),
    );
    if (changed == true) {
      await _loadAll();
    }
  }

  void _openWalletHistory() => Navigator.pushNamed(context, '/commission_history');
  void _openPublicPreview() => Navigator.pushNamed(context, '/livraison-demande');

  Future<void> _openVehicles() async {
    final id = _profil?['id'] as String?;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID livreur introuvable')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MesVehiculesPage(livreurId: id)),
    );
    if (changed == true) {
      await _loadAll();
    }
  }

  void _call() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appel non implémenté')),
    );
  }

  // ========= Redeem helpers =========

  Future<void> _redeemAndRefresh(String code) async {
    try {
      final res = await supabase.rpc('redeem_commission_code', params: {'p_code': code});
      if (res == true) {
        if (mounted) {
          setState(() {
            _walletBalance = 0; // feedback immédiat
          });
        }
        await _loadAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement enregistré')),
        );
      } else {
        throw 'Code invalide';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _scanQr() async {
    final code = await Navigator.pushNamed<String?>(context, '/scan_commission_qr');
    if (code != null && code.trim().isNotEmpty) {
      await _redeemAndRefresh(code.trim());
    }
  }

  Future<void> _enterCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Saisir un code de paiement'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Code (6 chiffres)…'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Valider')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    await _redeemAndRefresh(code);
  }

  // ========= Prix dynamique =========
  Future<void> _editPriceBottomSheet() async {
    final current = (_profil?['price_amount'] as num?)?.toDouble() ?? 0.0;
    final ctrl = TextEditingController(
      text: current.toStringAsFixed((current % 1 == 0) ? 0 : 2),
    );

    final res = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Modifier mon prix par livraison', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '$_walletCurrency ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                      Navigator.pop(ctx, v);
                    },
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (res == null) return;

    await supabase
        .from('livreurs')
        .update({
          'price_amount': res,
          'price_currency': _walletCurrency,
        })
        .eq('user_id', supabase.auth.currentUser!.id);

    if (!mounted) return;
    setState(() {
      _profil?['price_amount'] = res;
      _profil?['price_currency'] = _walletCurrency;
    });
  }

  // ========= UI helpers =========

  Color _barColor(double b) {
    if (b >= _capAmount) return Colors.red;         // bloqué
    if (b >= _capAmount * 0.6) return Colors.orange;
    return const Color(0xFF22C55E);
  }

  String _stateLabel(double b) {
    if (b >= _capAmount) return '🔴 à payer (bloqué)';
    if (b >= _capAmount * 0.6) return '🟡 à surveiller';
    return '🟢 OK';
  }

  Widget _profileVisual(String? mainUrl, String? badgeUrl) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: (mainUrl == null || mainUrl.isEmpty)
                ? Container(
                    height: 72, width: 72,
                    color: const Color(0xFFEDEDED),
                    child: const Icon(Icons.image),
                  )
                : Image.network(mainUrl, height: 72, width: 72, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: -4, bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: (badgeUrl == null || badgeUrl.isEmpty)
                  ? null
                  : NetworkImage(badgeUrl),
              child: (badgeUrl == null || badgeUrl.isEmpty) ? const Icon(Icons.local_shipping, size: 16) : null,
            ),
          ),
        ),
      ],
    );
  }

  // ========= GPS helpers (dashboard) =========

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await Geolocator.openLocationSettings();
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<void> _pushLocationOnce() async {
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Active la localisation et accepte la permission.')),
        );
      }
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      await supabase.rpc('upsert_driver_location', params: {
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      if (mounted) setState(() => _lastGpsAt = DateTime.now());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position envoyée.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur GPS : $e')),
        );
      }
    }
  }

  void _startLiveShare({Duration interval = const Duration(seconds: 20)}) {
    _gpsTimer?.cancel();
    setState(() => _shareLive = true);
    _gpsTimer = Timer.periodic(interval, (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 8),
        );
        await supabase.rpc('upsert_driver_location', params: {
          'lat': pos.latitude,
          'lng': pos.longitude,
        });
        if (mounted) setState(() => _lastGpsAt = DateTime.now());
      } catch (_) {
        // ignore
      }
    });
  }

  void _stopLiveShare() {
    _gpsTimer?.cancel();
    setState(() => _shareLive = false);
  }

  // ========= BUILD =========

  @override
  Widget build(BuildContext context) {
    final p = _profil;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace Livreur'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBackToRoles),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (p == null)
              ? const Center(child: Text('Profil introuvable'))
              : (_isBlocked)           // <<<<<<<<<<<<<< PAYWALL ICI
                  ? _paywallCard()
                  : _dashboardList(p),
    );
  }

  // ========= Sections =========

  Widget _dashboardList(Map<String, dynamic> p) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _validatedBanner(p),
          const SizedBox(height: 8),
          _gpsCard(), // <<< AJOUT : bloc localisation
          const SizedBox(height: 8),
          _profileCard(p),
          const SizedBox(height: 12),
          _totalsCard(),
          const SizedBox(height: 12),
          _commissionsCard(),
          const SizedBox(height: 12),
          _pendingCard(),
          const SizedBox(height: 12),
          _previewCard(),
          const SizedBox(height: 12),
          _vehiclesCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _validatedBanner(Map<String, dynamic> p) {
    final createdRaw = p['created_at'];
    final createdAt = (createdRaw == null) ? '' : createdRaw.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFBF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBAE6C8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Color(0xFF22C55E)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Profil validé', style: TextStyle(fontWeight: FontWeight.w600))),
          Text(
            'Créé le ${createdAt.isEmpty ? '—' : createdAt.split('T').first}',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ---- Carte Localisation ----
  Widget _gpsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Localisation / GPS', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pushLocationOnce,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Envoyer ma position'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Partager en temps réel'),
                  value: _shareLive,
                  onChanged: (v) => v ? _startLiveShare() : _stopLiveShare(),
                ),
              ),
            ],
          ),
          if (_lastGpsAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Dernier envoi : ${DateFormat('dd/MM/yyyy HH:mm:ss').format(_lastGpsAt!.toLocal())}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Astuce : active “temps réel” uniquement pendant ton service. '
            'Tu peux couper pour économiser la batterie.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ]),
      ),
    );
  }

  Widget _profileCard(Map<String, dynamic> p) {
    final nom = (p['nom'] ?? '—').toString();
    final prenom = (p['prenom'] ?? '').toString();
    final pro = (p['pro'] ?? false) == true;
    final zones = (p['zones'] ?? '—').toString();
    final negociable = (p['negociable'] == true);
    final phone = (p['phone'] ?? '—').toString();

    final photo1 = (p['photo1'] ?? '') as String?;
    final photo2 = (p['photo2'] ?? '') as String?;

    final priceAmount = (p['price_amount'] as num?)?.toDouble();
    final priceCurrency = (p['price_currency'] as String?) ?? _walletCurrency;

    final prixAffiche = (priceAmount == null || priceAmount == 0)
        ? (negociable ? 'À négocier' : '—')
        : _fmtMoney(priceCurrency, priceAmount);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 84, child: _profileVisual(photo1, photo2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${prenom.isEmpty ? '' : '$prenom '}$nom',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pro)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('PRO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                    ]), 
                    const SizedBox(height: 4),
                    Text((p['type_livraison'] ?? 'Livraison tout type').toString()),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.map_outlined, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Zones : $zones', maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(prixAffiche, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 16),
                      const Icon(Icons.phone, size: 16),
                      const SizedBox(width: 6),
                      Text(phone),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _call, icon: const Icon(Icons.call), label: const Text('Appeler')),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ActionChip(
                  label: Text(
                    priceAmount == null || priceAmount == 0
                        ? 'Fixer un prix'
                        : 'Prix: ${_fmtMoney(priceCurrency, priceAmount)}',
                  ),
                  avatar: const Icon(Icons.sell_outlined, size: 18),
                  onPressed: _editPriceBottomSheet,
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _openDemandes,
                  icon: const Icon(Icons.inbox_outlined),
                  label: Text(_pendingCount > 0
                      ? 'Voir les demandes (${_pendingCount.toString()})'
                      : 'Voir les demandes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _openEditProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier mon profil'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Totaux mensuels
  Widget _totalsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Statistiques du mois', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                _metricTile(icon: Icons.local_shipping_outlined, label: 'Livraisons', value: '$_monthDeliveries'),
                const SizedBox(width: 12),
                _metricTile(icon: Icons.attach_money, label: 'Revenus bruts', value: _fmtMoney(_walletCurrency, _monthGross)),
                const SizedBox(width: 12),
                _metricTile(icon: Icons.percent, label: 'Commission (10%)', value: _fmtMoney(_walletCurrency, _monthCommission)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile({required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Commission totale + barre de progression
  Widget _commissionsCard() {
    final ratio = (_walletBalance / _capAmount).clamp(0.0, 1.0);
    final color = _barColor(_walletBalance);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Commissions', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Solde : ${_fmtMoney(_walletCurrency, _walletBalance)}'),
              const SizedBox(width: 12),
              Text('(objectif ${_fmtMoney(_walletCurrency, _capAmount)})'),
              const Spacer(),
              Text('État : ${_stateLabel(_walletBalance)}'),
            ],
          ),
          const SizedBox(height: 4),
          Text('Taux du solde: ${(100 * _walletCommissionRateDisplay).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 12,
              value: ratio,
              color: color,
              backgroundColor: const Color(0xFFE5E7EB),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _enterCode,
                icon: const Icon(Icons.confirmation_number_outlined),
                label: const Text('Saisir un code'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner QR'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _openWalletHistory,
                icon: const Icon(Icons.history),
                label: const Text('Historique'),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  // ------- Page “À payer” si bloqué -------
  Widget _paywallCard() {
    final ratio = (_walletBalance / _capAmount).clamp(0.0, 1.0);
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Commissions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Solde : ${_fmtMoney(_walletCurrency, _walletBalance)}'),
                      const SizedBox(width: 12),
                      Text('(objectif ${_fmtMoney(_walletCurrency, _capAmount)})'),
                      const Spacer(),
                      const Text('État : 🔴 à payer', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 14,
                      value: ratio,
                      color: Colors.red,
                      backgroundColor: const Color(0xFFE5E7EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ton objectif est atteint. Règle ton solde pour accéder à ton interface.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _enterCode,
                        icon: const Icon(Icons.confirmation_number_outlined),
                        label: const Text('Saisir un code'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scanner QR'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _openWalletHistory,
                        icon: const Icon(Icons.history),
                        label: const Text('Historique'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Demandes en attente'),
              subtitle: Text(
                _pendingCount == 0
                    ? 'Aucune demande reçue pour le moment'
                    : '${_pendingCount} demande(s) reçue(s)',
              ),
              trailing: const Icon(Icons.visibility_off),
              enabled: false, // pas cliquable
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualiser après paiement'),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: const Text('Demandes en attente'),
        subtitle: Text(_pendingCount == 0
            ? 'Aucune demande assignée pour le moment.'
            : '$_pendingCount nouvelle(s) demande(s) en attente.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openDemandes,
      ),
    );
  }

  Widget _previewCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: const Icon(Icons.visibility_outlined),
        title: const Text('Aperçu public'),
        subtitle: const Text('Ouvre la page “Demander une livraison”.'),
        onTap: _openPublicPreview,
      ),
    );
  }

  Widget _vehiclesCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.directions_car),
            title: Text('Véhicules'),
            subtitle: Text('Gère tes véhicules (photos, zones).'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Ajouter un véhicule'),
            onTap: _openVehicles,
          ),
        ],
      ),
    );
  }
}
