// lib/pages/partenaire_dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support_chat_page.dart';

class PartenaireDashboardPage extends StatefulWidget {
  const PartenaireDashboardPage({Key? key}) : super(key: key);

  @override
  State<PartenaireDashboardPage> createState() => _PartenaireDashboardPageState();
}

class _PartenaireDashboardPageState extends State<PartenaireDashboardPage> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? partenaire; // ligne partenaires
  String? partnerId;

  // Vue devise (depuis v_partner_profile)
  String _currencyCode = 'EUR';
  String _currencySymbol = '€';
  int _currencyDecimals = 2;
  double _perEur = 1.0; // 1 EUR -> combien dans la monnaie du partenaire

  // partner_codes.kind = 'taxi' | 'livreur'
  List<Map<String, dynamic>> taxiAboCodes = [];
  List<Map<String, dynamic>> livreurCodes = [];

  bool loading = true;

  // KPIs (mois en cours) — stockés en EUR côté calcul, puis convertis pour affichage
  int codesThisMonth = 0;     // tous codes générés (taxi+livreur) ce mois
  int clientsActives = 0;     // codes utilisés ce mois
  double totalCashEur = 0;    // somme(amount) EUR des codes utilisés (mois)
  double partnerShareEur = 0; // 30% EUR du totalCash
  static const double partnerRate = 0.30;

  RealtimeChannel? _codesChan; // realtime

  Color get brand => const Color(0xFF084C28);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _codesChan?.unsubscribe();
    super.dispose();
  }

  // ---------- Helpers ----------
  Map<String, dynamic>? _asRow(dynamic res) {
    if (res == null) return null;
    if (res is Map) return Map<String, dynamic>.from(res as Map);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return null;
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == 't' || s == '1' || s == 'yes' || s == 'validated';
    }
    return false;
  }

  bool _coalesceValidated(Map p) {
    if (_toBool(p['est_valide'])) return true;
    if (_toBool(p['is_valid'])) return true;
    if (_toBool(p['approved'])) return true;
    if (_toBool(p['verified'])) return true;
    final status = (p['status'] ?? '').toString().toLowerCase();
    return status == 'approved' || status == 'validated';
  }

  bool _coalesceBlocked(Map p) {
    if (_toBool(p['est_bloque'])) return true;
    if (_toBool(p['is_blocked'])) return true;
    final status = (p['status'] ?? '').toString().toLowerCase();
    return status == 'blocked';
  }

  // Affichage argent
  double _toLocal(double amountEur) => amountEur * _perEur;
  String _moneyEur(double eur) =>
      '$_currencySymbol ${_toLocal(eur).toStringAsFixed(_currencyDecimals)}';

  String _moneyRaw(String code, String symbol, num amount, {int? decimals}) {
    final d = decimals ?? ((amount % 1 == 0) ? 0 : 2);
    final sym = symbol.isNotEmpty ? symbol : code;
    return '$sym ${amount.toStringAsFixed(d)}';
  }

  // ---------- Sélection depuis partner_codes ----------
  Future<List<Map<String, dynamic>>> _selectPartnerCodes({
    required String kind,
    required String partnerId,
  }) async {
    final res = await supabase
        .from('partner_codes')
        .select(
            'id, code, partner_id, amount, currency, kind, status, '
            'created_at, redeemed_at, redeemed_by, period, cars_count, '
            'immatriculation, livreur_phone, meta')
        .eq('partner_id', partnerId)
        .eq('kind', kind)
        .order('created_at', ascending: false)
        .limit(100);

    final list = (res as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();

    return list.map((m) {
      m['currency_code'] = (m['currency'] ?? '').toString();
      m['cars'] = m['cars_count'];
      m['is_redeemed'] = (m['status'] == 'used') || (m['redeemed_at'] != null);
      return m;
    }).toList();
  }

  // ---------- KPI mois en cours ----------
  Future<void> _recomputeKpis() async {
  final pid = partnerId;           // ← copie locale
  if (pid == null) return;         // ← garde-fou

  final now = DateTime.now();
  final firstDay = DateTime(now.year, now.month, 1).toIso8601String();

  // 1) codes générés (toutes catégories) ce mois
  final genRes = await supabase
      .from('partner_codes')
      .select('id')
      .eq('partner_id', pid)       // ← utilise pid (non-null)
      .gte('created_at', firstDay);

  codesThisMonth = (genRes as List).length;

  // 2) codes utilisés ce mois
  final usedRes = await supabase
      .from('partner_codes')
      .select('amount, redeemed_at, status')
      .eq('partner_id', pid)       // ← utilise pid (non-null)
      .gte('redeemed_at', firstDay)
      .or('status.eq.used,redeemed_at.not.is.null');

  double sumEur = 0;
  int countClients = 0;

  for (final r in (usedRes as List)
      .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))) {
    countClients += 1;
    sumEur += _asDouble(r['amount']);
  }

  if (!mounted) return;
  setState(() {
    clientsActives  = countClients;
    totalCashEur    = sumEur;
    partnerShareEur = totalCashEur * partnerRate;
  });
}

  // ---------- Chargement principal ----------
  Future<void> _loadAll() async {
    setState(() => loading = true);
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      // 1) Vue profil partenaire (devise prête à l’emploi)
      final v = await supabase
          .from('v_partner_profile')
          .select(
              'id, user_id, prenom, nom, status, kyc_status, currency_code, currency_symbol, per_eur, currency_decimals')
          .eq('user_id', user.id)
          .single();

      final vMap = Map<String, dynamic>.from(v as Map);
      partnerId = (vMap['id'] ?? '').toString();
      partenaire = vMap;

      _currencyCode = (vMap['currency_code'] ?? 'EUR').toString();
      _currencySymbol = (vMap['currency_symbol'] ?? _currencyCode).toString();
      _perEur = _asDouble(vMap['per_eur']); // 1 EUR -> monnaie locale
      if (_perEur <= 0) _perEur = 1.0;
      _currencyDecimals = (vMap['currency_decimals'] ?? 2) as int;

      // 2) Codes TAXI / LIVREUR
      final taxiRes = await _selectPartnerCodes(kind: 'taxi', partnerId: partnerId!);
      final livrRes = await _selectPartnerCodes(kind: 'livreur', partnerId: partnerId!);

      // 3) KPI
      await _recomputeKpis();

      if (!mounted) return;
      setState(() {
        taxiAboCodes = taxiRes;
        livreurCodes = livrRes;
        loading = false;
      });

      // ---------- Realtime v2 ----------
      _codesChan?.unsubscribe();

      final chan = supabase.channel('public:partner_codes:$partnerId');

      // INSERT
      chan.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'partner_codes',
        callback: (payload) {
          final newRow = Map<String, dynamic>.from(payload.newRecord);
          if (newRow['partner_id']?.toString() != partnerId) return;

          newRow['currency_code'] = (newRow['currency'] ?? '').toString();
          newRow['cars'] = newRow['cars_count'];
          newRow['is_redeemed'] = (newRow['status'] == 'used') || (newRow['redeemed_at'] != null);

          setState(() {
            if (newRow['kind'] == 'taxi') {
              taxiAboCodes.insert(0, newRow);
            } else if (newRow['kind'] == 'livreur') {
              livreurCodes.insert(0, newRow);
            }
          });
          _recomputeKpis();
        },
      );

      // UPDATE
      chan.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'partner_codes',
        callback: (payload) {
          final newRow = Map<String, dynamic>.from(payload.newRecord);
          if (newRow['partner_id']?.toString() != partnerId) return;

          final list = (newRow['kind'] == 'livreur') ? livreurCodes : taxiAboCodes;
          final idx = list.indexWhere((e) => e['id'] == newRow['id']);
          if (idx >= 0) {
            newRow['currency_code'] = (newRow['currency'] ?? '').toString();
            newRow['cars'] = newRow['cars_count'];
            newRow['is_redeemed'] = (newRow['status'] == 'used') || (newRow['redeemed_at'] != null);
            setState(() => list[idx] = newRow);
          }
          _recomputeKpis();
        },
      );

      chan.subscribe();
      _codesChan = chan;
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement: $e')),
      );
    }
  }

  bool get _isBlocked => _coalesceBlocked(partenaire ?? {});
  bool get _isValidated => _coalesceValidated(partenaire ?? {});

  // ======== Générer code TAXI (RPC uniquement) ========
  Future<void> _createTaxiAboCode() async {
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Votre compte est bloqué. Génération désactivée.")),
      );
      return;
    }
    if (!_isValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Votre compte n’est pas encore validé.")),
      );
      return;
    }

    final plateCtrl = TextEditingController();
    String period = 'mensuel';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Générer un code (Taxi • Abonnement)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: plateCtrl,
              decoration: const InputDecoration(
                labelText: 'Immatriculation (première voiture)',
                hintText: 'ex: 253AT73',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: period,
              decoration: const InputDecoration(labelText: 'Période'),
              items: const [
                DropdownMenuItem(value: 'mensuel', child: Text('Mensuel')),
                DropdownMenuItem(value: 'annuel', child: Text('Annuel')),
              ],
              onChanged: (v) => period = v ?? 'mensuel',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
        ],
      ),
    );

    if (ok != true) return;

    final immatInput = plateCtrl.text.trim();
    if (immatInput.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisis une immatriculation')),
      );
      return;
    }

    try {
      final rpc = await supabase.rpc('partner_generate_subscription_code_by_plate', params: {
        'p_immatriculation': immatInput,
        'p_period': period,
      });
      final row = _asRow(rpc);
      if (row == null) throw 'Aucun résultat du serveur';

      final String code = (row['code'] ?? '').toString();
      final double amount = _asDouble(row['amount']);
      final int cars = (row['car_count'] as int?) ?? int.tryParse('${row['car_count']}') ?? 0;
      final String curr = (row['currency_code'] ?? _currencyCode).toString();
      final String currSym = (row['currency_symbol'] ?? _currencySymbol).toString();
      final String per = (row['period'] ?? period).toString();
      final String immat = (row['immatriculation'] ?? immatInput).toString();

      setState(() {
        taxiAboCodes.insert(0, {
          'code': code,
          'amount': amount,
          'currency_code': curr,
          'currency_symbol': currSym,
          'kind': 'taxi',
          'status': 'pending',
          'period': per,
          'cars': cars,
          'immatriculation': immat,
          'created_at': DateTime.now().toIso8601String(),
          'is_redeemed': false,
        });
      });

      await Clipboard.setData(ClipboardData(text: code));
      _recomputeKpis();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Code Taxi (Abonnement)'),
          content: Text(
            'Code: $code\n'
            'Montant: ${_moneyRaw(curr, currSym, amount)}\n'
            'Voitures: $cars\n'
            'Période: ${per == 'annuel' ? 'Annuel' : 'Mensuel'}\n'
            'Immatriculation: $immat',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur génération: $e')),
      );
    }
  }

  // ======== Générer code LIVREUR (RPC uniquement) ========
  Future<void> _createLivreurCode() async {
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Votre compte est bloqué. Génération désactivée.")),
      );
      return;
    }
    if (!_isValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Votre compte n’est pas encore validé.")),
      );
      return;
    }

    // demande le téléphone du livreur (dynamique)
    final phoneCtrl = TextEditingController();
    final phone = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Créer un code pour un livreur'),
        content: TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone du livreur',
            hintText: '+269…',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, phoneCtrl.text.trim()), child: const Text('Créer')),
        ],
      ),
    );

    if (phone == null || phone.isEmpty) return;

    try {
      final rpc = await supabase.rpc('create_livreur_code_by_phone', params: {
        'p_phone': phone.trim(),
      });

      final row = _asRow(rpc);
      if (row == null) throw 'Échec création code';

      final String code = (row['code'] ?? '').toString();
      final double amount = _asDouble(row['amount']);
      final String curr = (row['currency'] ?? row['currency_code'] ?? _currencyCode).toString();
      final String currSym = (row['currency_symbol'] ?? _currencySymbol).toString();

      setState(() {
        livreurCodes.insert(0, {
          'code': code,
          'amount': amount,
          'currency_code': curr,
          'currency_symbol': currSym,
          'kind': 'livreur',
          'status': 'pending',
          'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
          'livreur_phone': row['livreur_phone'] ?? phone,
          'meta': row['meta'] ?? {},
          'is_redeemed': false,
        });
      });

      await Clipboard.setData(ClipboardData(text: code));
      _recomputeKpis();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Code livreur créé'),
          content: Text('Code: $code\nMontant: ${_moneyRaw(curr, currSym, amount)}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isMobile = MediaQuery.of(context).size.width < 760;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Espace Partenaire'),
        actions: [
          IconButton(onPressed: _loadAll, tooltip: 'Recharger', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final stats = [
            _kpi('Codes générés (mois)', '$codesThisMonth', Icons.qr_code_2),
            _kpi('Clients activés (mois)', '$clientsActives', Icons.verified),
            _kpi('Total cash (brut) (mois)', _moneyEur(totalCashEur), Icons.payments),
            _kpi('À payer partenaire (30%)', _moneyEur(partnerShareEur), Icons.account_balance_wallet),
          ];

          final gridLeft = Column(
            children: [
              _profileCard(),
              const SizedBox(height: 12),
              _codesTaxiAboCard(),
              const SizedBox(height: 12),
              _codesLivreurCard(),
            ],
          );

          final gridRight = Column(
            children: [
              _paymentCard(),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: stats),
            ],
          );

          if (isMobile) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [gridLeft, const SizedBox(height: 16), gridRight, const SizedBox(height: 24)]),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: gridLeft),
                const SizedBox(width: 16),
                Expanded(child: gridRight),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        onPressed: () {
          if (partnerId == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SupportChatPage(partnerId: partnerId!)),
          );
        },
        icon: const Icon(Icons.help_outline),
        label: const Text('Besoin d’aide ?'),
      ),
    );
  }

  Widget _profileCard() {
    final nom = '${partenaire?['prenom'] ?? ''} ${partenaire?['nom'] ?? ''}'.trim();
    final validated = _isValidated;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: brand.withOpacity(0.1),
              child: const Icon(Icons.person, color: Colors.black87),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom.isEmpty ? 'Partenaire' : nom,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(validated ? Icons.verified : Icons.hourglass_bottom,
                        size: 16, color: validated ? Colors.green : Colors.orange),
                    const SizedBox(width: 6),
                    Text(validated ? 'Compte validé' : 'En attente de validation'),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Devise : $_currencyCode', style: const TextStyle(color: Colors.black54)),
              ]), 
            ),
            TextButton.icon(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/roles', (_) => false),
              icon: const Icon(Icons.switch_account),
              label: const Text('Mes rôles'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentCard() {
    final link = _paymentLink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Paiement en ligne', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(link, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: brand, foregroundColor: Colors.white),
            onPressed: () => Clipboard.setData(ClipboardData(text: link)).then(
              (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié 👍'))),
            ),
            icon: const Icon(Icons.copy),
            label: const Text('Copier le lien'),
          ),
        ]),
      ),
    );
  }

  Widget _kpi(String title, String value, IconData icon) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ]),
        ]),
      ),
    );
  }

  Widget _codesTaxiAboCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Codes Taxi (Abonnement)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: brand, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _createTaxiAboCode,
              icon: const Icon(Icons.add),
              label: const Text('Nouveau code (Taxi • Abo)'),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (taxiAboCodes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Aucun code abonnement taxi pour le moment.'),
            ),
          ...taxiAboCodes.map((c) {
            final code = (c['code'] ?? '').toString();
            final isRedeemed = c['is_redeemed'] == true || (c['redeemed_at'] != null);
            final amount = _asDouble(c['amount']);
            final createdAt = DateTime.tryParse(c['created_at']?.toString() ?? '');
            final cc = (c['currency_code'] ?? _currencyCode).toString();
            final sym = (c['currency_symbol'] ?? _currencySymbol).toString();

            final cars = c['cars'];
            final period = c['period'];
            final immat = c['immatriculation'];

            final detail = <String>[];
            if (amount > 0) detail.add('Montant: ${_moneyRaw(cc, sym, amount)}');
            if (cars != null) detail.add('Voitures: $cars');
            if (period != null) detail.add('Période: ${period == 'annuel' ? 'Annuel' : 'Mensuel'}');
            if (immat != null) detail.add('Immatriculation: $immat');

            return ListTile(
              dense: true,
              leading: Icon(isRedeemed ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isRedeemed ? Colors.green : Colors.grey),
              title: Text(code, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                if (createdAt != null) 'Créé le ${createdAt.day}/${createdAt.month}/${createdAt.year}',
                if (detail.isNotEmpty) detail.join(' • '),
              ].where((e) => e.isNotEmpty).join(' • ')),
              trailing: IconButton(
                tooltip: 'Copier',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: code)).then(
                  (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié'))),
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _codesLivreurCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Codes Livreurs (barre commission)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: brand, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _createLivreurCode,
              icon: const Icon(Icons.add),
              label: const Text('Nouveau code (Livreur)'),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (livreurCodes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Aucun code livreur pour le moment.'),
            ),
          ...livreurCodes.map((c) {
            final code = (c['code'] ?? '').toString();
            final isRedeemed = c['is_redeemed'] == true || (c['redeemed_at'] != null);
            final amount = _asDouble(c['amount']);
            final createdAt = DateTime.tryParse(c['created_at']?.toString() ?? '');
            final cc = (c['currency_code'] ?? _currencyCode).toString();
            final sym = (c['currency_symbol'] ?? _currencySymbol).toString();

            return ListTile(
              dense: true,
              leading: Icon(isRedeemed ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isRedeemed ? Colors.green : Colors.grey),
              title: Text(code, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                if (createdAt != null) 'Créé le ${createdAt.day}/${createdAt.month}/${createdAt.year}',
                if (amount > 0) 'Montant: ${_moneyRaw(cc, sym, amount)}',
              ].join(' • ')),
              trailing: IconButton(
                tooltip: 'Copier',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: code)).then(
                  (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié'))),
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }

  String _paymentLink() {
    const base = String.fromEnvironment('PAY_BASE_URL', defaultValue: 'https://suivitaxi.com/pay');
    return '$base?partner=$partnerId';
  }
}
