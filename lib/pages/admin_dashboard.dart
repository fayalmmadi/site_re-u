// lib/pages/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ==================== CONFIG BUSINESS ====================
const double kOwnerSharePartners = 0.70; // ta part sur partenaires (70%)
const double kPartnerShare       = 0.30; // part partenaire (30%)
const double kOwnerShareDrivers  = 0.10; // ta commission livreurs (10%)
const double kDriverShare        = 0.90; // net livreur (90%)

/// Prix fixe par activation (fallback si amount null)
const double kPricePerActivation = 10.0;

/// ==================== SCHÉMA ====================
/// PARTENAIRES
const String kTablePartners       = 'partenaires';
const String kTablePartnerCodes   = 'partner_codes';
const String kColPartnerIdInCodes = 'partner_id';
const String kColIsValid          = 'est_valide';
const String kColIsBlocked        = 'est_bloque';

/// LIVREURS
const String kTableDrivers        = 'livreurs';

/// Vue agrégée livreurs (OK côté livreur)
/// Colonnes attendues: user_id, month(YYYY-MM-01), deliveries_count, gross_revenue, app_commission
const String kViewDriverMonthStats = 'v_livreur_stats_month';

/// COLS génériques
const String kColId        = 'id';
const String kColCreatedAt = 'created_at';

/// Devise : on ne charge que celles-ci (tu peux en ajouter)
const List<String> kPreferredCurrencyCodes = [
  'EUR','KMF','XOF','XAF','MAD','TND','DZD','USD','GBP','CHF','NGN','ZAR','KES','CDF','GHS','EGP'
];

enum AdminTab  { partners, drivers }
enum StatusTab { pending, approved, refused, blocked }

class _Cur {
  final String code;
  final String symbol;
  final double perEur;  // combien d’unités locales pour 1 EUR
  final int decimals;
  _Cur({required this.code,required this.symbol,required this.perEur,required this.decimals});
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supa = Supabase.instance.client;

  AdminTab  currentTab    = AdminTab.partners;
  StatusTab statusTab     = StatusTab.approved;
  DateTime  selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final _searchCtrl       = TextEditingController();

  bool loading = true;

  // KPIs (toujours stockés en EUR puis convertis à l’affichage)
  int    kpiCountA = 0;
  double kpiGross  = 0.0;
  double kpiOwner  = 0.0;
  double kpiOther  = 0.0;

  // Liste affichée
  List<_AdminCard> items = [];

  // ===== Devise d’affichage =====
  final Map<String,_Cur> _currs = {};
  String _curCode = 'EUR';
  String _curSymbol = '€';
  int    _curDecimals = 2;
  double _perEur = 1.0; // 1 EUR -> combien en devise affichée

  // ===== Période mensuelle =====
  DateTime get monthStart => DateTime(selectedMonth.year, selectedMonth.month, 1);
  DateTime get monthEnd   => DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
  String  get monthLabel  => DateFormat.yMMMM('fr_FR').format(selectedMonth);
  String  get monthIsoDay1 => DateFormat('yyyy-MM-01').format(monthStart);

  @override
  void initState() {
    super.initState();
    _initCurrencies().then((_) => _reloadAll());
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _prevMonth(){ setState((){ selectedMonth = DateTime(selectedMonth.year, selectedMonth.month-1, 1); loading = true;}); _reloadAll(); }
  void _nextMonth(){ setState((){ selectedMonth = DateTime(selectedMonth.year, selectedMonth.month+1, 1); loading = true;}); _reloadAll(); }
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year-5,1,1),
      lastDate : DateTime(now.year+5,12,31),
      initialDate: selectedMonth,
      locale: const Locale('fr','FR'),
    );
    if (picked != null) {
      setState((){ selectedMonth = DateTime(picked.year, picked.month, 1); loading = true;});
      _reloadAll();
    }
  }

  // ==================== Devises ====================
  Future<void> _initCurrencies() async {
    try {
      final rows = await supa
          .from('currencies')
          .select('code, symbol, per_eur, decimals')
          .inFilter('code', kPreferredCurrencyCodes);

      _currs.clear();
      for (final r in (rows as List)) {
        final code = (r['code']??'').toString().toUpperCase();
        if (code.isEmpty) continue;
        _currs[code] = _Cur(
          code: code,
          symbol: (r['symbol']??code).toString(),
          perEur: (r['per_eur'] as num?)?.toDouble() ?? 1.0,
          decimals: (r['decimals'] ?? 2) as int,
        );
      }
    } catch (_) {/* ignore */ }
    _currs.putIfAbsent('EUR', ()=>_Cur(code:'EUR', symbol:'€', perEur:1.0, decimals:2));
    _applyCurrency('EUR'); // défaut
  }

  void _applyCurrency(String code){
    final c = _currs[code] ?? _currs['EUR']!;
    _curCode = c.code; _curSymbol = c.symbol; _curDecimals = c.decimals; _perEur = c.perEur;
    if (mounted) setState((){});
  }

  double _toDisplay(double amountEur) => amountEur * _perEur;
  String _money(double amountEur) => '$_curSymbol ${_toDisplay(amountEur).toStringAsFixed(_curDecimals)}';

  // ==================== Reload ====================
  Future<void> _reloadAll() async {
    try {
      _searchCtrl.text = '';
      if (currentTab == AdminTab.partners) {
        await _loadPartnersData();   // ✅ version correcte côté partenaires (depuis ton 2e fichier)
      } else {
        await _loadDriversData();    // ✅ version correcte côté livreurs (depuis ton 1er fichier)
      }
    } catch (e) {
      debugPrint('Admin load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ---------- helpers ----------
  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
  bool _true(Map m, String k) => m[k] == true || m[k]?.toString() == 'true';

  String _statusFromRecord(Map m) {
    if (m.containsKey(kColIsBlocked) && _true(m, kColIsBlocked)) return 'blocked';
    if (m.containsKey(kColIsValid)  && _true(m, kColIsValid))    return 'approved';
    final s = m['status']?.toString();
    if (s == null || s.isEmpty) return 'pending';
    return s;
  }

  static String _safeYearMonth(dynamic iso){
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso.toString());
    if (dt == null) return '—';
    return DateFormat('yyyy-MM').format(dt);
  }

  // ===================== PARTENAIRES (CORRECT) =====================
  Future<void> _loadPartnersData() async {
    final fromIso = monthStart.toIso8601String();
    final toIso   = monthEnd.toIso8601String();

    // 1) Codes générés dans le mois (kind = taxi)
    final codesRes = await supa
        .from(kTablePartnerCodes)
        .select(kColId)
        .eq('kind', 'taxi')
        .gte(kColCreatedAt, fromIso)
        .lt(kColCreatedAt, toIso);
    final codesCount = (codesRes as List).length;

    // 2) Brut du mois = somme(amount) des codes utilisés ce mois (status used/redeemed) sur redeemed_at
    final usedRes = await supa
        .from(kTablePartnerCodes)
        .select('amount')
        .eq('kind', 'taxi')
        .inFilter('status', ['used','redeemed'])
        .gte('redeemed_at', fromIso)
        .lt('redeemed_at', toIso);

    double grossEur = 0.0;
    for (final row in (usedRes as List)) {
      final amt = _asDouble(row['amount']);
      grossEur += (amt > 0 ? amt : kPricePerActivation);
    }

    setState(() {
      kpiCountA = codesCount;
      kpiGross  = grossEur;
      kpiOwner  = grossEur * kOwnerSharePartners; // 70 %
      kpiOther  = grossEur * kPartnerShare;       // 30 %
    });

    // 3) Liste partenaires + stats par partenaire (mois)
    final rows = await supa
        .from(kTablePartners)
        .select('*')
        .order(kColCreatedAt, ascending: false);

    final List<_AdminCard> list = [];
    for (final p in (rows as List)) {
      final st = _statusFromRecord(p);
      final keep = switch (statusTab) {
        StatusTab.approved => st == 'approved',
        StatusTab.blocked  => st == 'blocked',
        StatusTab.pending  => st == 'pending',
        StatusTab.refused  => st == 'refused',
      };
      if (!keep) continue;

      final pid = p[kColId].toString();

      // Codes générés par CE partenaire (mois)
      final pcodes = await supa
          .from(kTablePartnerCodes)
          .select(kColId)
          .eq('kind', 'taxi')
          .eq(kColPartnerIdInCodes, pid)
          .gte(kColCreatedAt, fromIso)
          .lt(kColCreatedAt, toIso);
      final nbCodes = (pcodes as List).length;

      // Brut CE partenaire (mois) via amount/fallback
      final pused = await supa
          .from(kTablePartnerCodes)
          .select('amount')
          .eq('kind', 'taxi')
          .eq(kColPartnerIdInCodes, pid)
          .inFilter('status', ['used','redeemed'])
          .gte('redeemed_at', fromIso)
          .lt('redeemed_at', toIso);

      double pGrossEur = 0.0;
      for (final r in (pused as List)) {
        final amt = _asDouble(r['amount']);
        pGrossEur += (amt > 0 ? amt : kPricePerActivation);
      }

      list.add(
        _AdminCard(
          id: pid,
          avatarUrl: p['avatar_url']?.toString(),
          title: [p['prenom']??'', p['nom']??'']
              .where((e)=>e.toString().isNotEmpty)
              .join(' ')
              .trim(),
          subtitle: 'Créé le : ${_safeYearMonth(p[kColCreatedAt])} • Codes générés (mois) : $nbCodes',
          line2: 'Brut (mois) : ${_money(pGrossEur)} • Ta part 70 % : ${_money(pGrossEur*kOwnerSharePartners)} • Partenaire 30 % : ${_money(pGrossEur*kPartnerShare)}',
          status: st,
          kind: AdminTab.partners,
        ),
      );
    }

    setState(() => items = list);
  }

  // ===================== LIVREURS (CORRECT) =====================
  /// Lit la vue v_livreur_stats_month (user_id, month, deliveries_count, gross_revenue, app_commission)
  Future<void> _loadDriversData() async {
    // 1) Stats du mois sélectionné (clé = 'month' au format 'YYYY-MM-01')
    final stats = await supa
        .from(kViewDriverMonthStats)
        .select('user_id, month, deliveries_count, gross_revenue, app_commission')
        .eq('month', monthIsoDay1);

    // KPIs globaux
    int deliveries = 0;
    double gross = 0, appCom = 0, net = 0;

    final List rows = (stats as List);
    for (final r in rows) {
      final gr  = _asDouble(r['gross_revenue']);
      final com = _asDouble(r['app_commission']);
      deliveries += _asInt(r['deliveries_count']);
      gross += gr;
      appCom += com;
      net += (gr - com);
    }

    setState(() {
      kpiCountA = deliveries; // Livraisons (mois)
      kpiGross  = gross;      // Revenus totaux base EUR
      kpiOwner  = appCom;     // Ma part 10 %
      kpiOther  = net;        // Net livreur
    });

    // 2) Index stats par user_id
    final Map<String, Map<String, dynamic>> byUserId = {};
    for (final r in rows) {
      final uid = (r['user_id'] ?? '').toString();
      if (uid.isNotEmpty) byUserId[uid] = r as Map<String, dynamic>;
    }

    // 3) Charger les livreurs (avec user_id) et mapper
    final drivers = await supa
        .from(kTableDrivers)
        .select('*')
        .order(kColCreatedAt, ascending: false);

    final List<_AdminCard> list = [];
    for (final d in (drivers as List)) {
      final st = _statusFromRecord(d);
      final keep = switch (statusTab) {
        StatusTab.approved => st == 'approved',
        StatusTab.blocked  => st == 'blocked',
        StatusTab.pending  => st == 'pending',
        StatusTab.refused  => st == 'refused',
      };
      if (!keep) continue;

      final did    = d[kColId].toString();
      final userId = d['user_id']?.toString(); // requis pour matcher la vue

      final s      = (userId != null) ? byUserId[userId] : null;
      final dCnt   = _asInt(s?['deliveries_count']);
      final dGross = _asDouble(s?['gross_revenue']);
      final dComm  = _asDouble(s?['app_commission']);
      final dNet   = dGross - dComm;

      list.add(
        _AdminCard(
          id: did,
          avatarUrl: d['avatar_url']?.toString(),
          title: [d['prenom']??'', d['nom']??'']
              .where((e)=>e.toString().trim().isNotEmpty)
              .join(' ')
              .trim(),
          subtitle: 'Créé le : ${_safeYearMonth(d[kColCreatedAt])} • Livraisons (mois) : $dCnt',
          line2: 'Revenus : ${_money(dGross)} • Ma part 10 % : ${_money(dComm)} • Net livreur : ${_money(dNet)}',
          status: st,
          kind: AdminTab.drivers,
        ),
      );
    }

    setState(() => items = list);
  }

  // ---------- Actions ----------
  Future<void> _approve(String id) async {
    final table = currentTab == AdminTab.partners ? kTablePartners : kTableDrivers;
    await supa.from(table).update({
      if (table == kTablePartners) kColIsValid: true,
      if (table == kTablePartners) kColIsBlocked: false,
      'status': 'approved'
    }).eq(kColId, id);
    _reloadAll();
  }

  Future<void> _reject(String id) async {
    final table = currentTab == AdminTab.partners ? kTablePartners : kTableDrivers;
    await supa.from(table).update({
      if (table == kTablePartners) kColIsValid: false,
      'status': 'refused'
    }).eq(kColId, id);
    _reloadAll();
  }

  Future<void> _block(String id) async {
    final table = currentTab == AdminTab.partners ? kTablePartners : kTableDrivers;
    await supa.from(table).update({
      if (table == kTablePartners) kColIsBlocked: true,
      'status': 'blocked'
    }).eq(kColId, id);
    _reloadAll();
  }

  // ---------- Recherche locale ----------
  List<_AdminCard> get filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((e) =>
      e.title.toLowerCase().contains(q) ||
      e.subtitle.toLowerCase().contains(q)
    ).toList();
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    final isPartners = currentTab == AdminTab.partners;
    return Scaffold(
      appBar: AppBar(title: const Text('Administration'), centerTitle: true),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildTopSwitch(),
          const SizedBox(height: 12),
          _buildMonthBarWithCurrency(),
          const SizedBox(height: 8),
          _buildKpis(isPartners),
          const SizedBox(height: 8),
          _buildStatusTabs(),
          Padding(padding: const EdgeInsets.fromLTRB(16,8,16,0), child: _buildSearch()),
          const SizedBox(height: 8),
          Expanded(child: loading ? const Center(child:CircularProgressIndicator()) : _buildList()),
        ],
      ),
    );
  }

  Widget _buildTopSwitch(){
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal:16),
      child: Row(children:[
        Expanded(child:_pillButton(label:'Partenaires',active: currentTab==AdminTab.partners,onTap:(){
          if(currentTab!=AdminTab.partners){ setState((){ currentTab=AdminTab.partners; statusTab=StatusTab.approved; loading=true;}); _reloadAll(); }
        })),
        const SizedBox(width:12),
        Expanded(child:_pillButton(label:'Livreurs',active: currentTab==AdminTab.drivers,onTap:(){
          if(currentTab!=AdminTab.drivers){ setState((){ currentTab=AdminTab.drivers; statusTab=StatusTab.approved; loading=true;}); _reloadAll(); }
        })),
      ]),
    );
  }

  Widget _buildMonthBarWithCurrency(){
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal:16),
      child: Row(children:[
        IconButton(onPressed:_prevMonth, icon: const Icon(Icons.chevron_left)),
        InkWell(
          onTap:_pickMonth,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal:12, vertical:8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.grey.shade200),
            child: Row(mainAxisSize: MainAxisSize.min, children:[
              const Icon(Icons.calendar_month), const SizedBox(width:8),
              Text(monthLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        IconButton(onPressed:_nextMonth, icon: const Icon(Icons.chevron_right)),
        const Spacer(),
        // Sélecteur devise
        if (_currs.isNotEmpty)
          DropdownButton<String>(
            value: _curCode,
            underline: const SizedBox.shrink(),
            items: _currs.values.map((c) =>
              DropdownMenuItem(value: c.code, child: Text('${c.code} (${c.symbol})'))
            ).toList(),
            onChanged: (v){ if(v!=null) _applyCurrency(v); },
          ),
        const SizedBox(width: 8),
        Text('Données filtrées par mois', style: TextStyle(color: Colors.grey.shade600)),
      ]),
    );
  }

  Widget _buildKpis(bool isPartners){
    final aTitle = isPartners ? 'Codes générés (mois)' : 'Livraisons (mois)';
    final bTitle = isPartners ? 'Brut (mois)'        : 'Revenus totaux';
    final cTitle = isPartners ? 'Ta part 70 %'       : 'Ma part 10 %';
    final dTitle = isPartners ? 'Partenaires 30 %'   : 'Gains nets livreurs';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal:16),
      child: Wrap(
        spacing:12, runSpacing:12,
        children:[
          _kpiCard(title:aTitle, value:kpiCountA.toString()),
          _kpiCard(title:bTitle, value:_money(kpiGross)),
          _kpiCard(title:cTitle, value:_money(kpiOwner)),
          _kpiCard(title:dTitle, value:_money(kpiOther)),
        ],
      ),
    );
  }

  Widget _buildStatusTabs(){
    Widget chip(StatusTab t, String label){
      final active = statusTab==t;
      return ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_){ setState(()=>statusTab=t); _reloadAll(); },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal:16),
      child: Wrap(spacing:8, children:[
        chip(StatusTab.pending,'En attente'),
        chip(StatusTab.approved,'Approuvés'),
        chip(StatusTab.refused,'Refusés'),
        chip(StatusTab.blocked,'Bloqués'),
      ]),
    );
  }

  Widget _buildSearch(){
    return TextField(
      controller: _searchCtrl,
      onChanged: (_)=>setState((){}),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Rechercher (nom, email, téléphone...)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal:12, vertical:12),
      ),
    );
  }

  Widget _buildList(){
    if(filtered.isEmpty) return const Center(child: Text('Aucun résultat'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16,8,16,24),
      itemBuilder: (_,i)=>_cardTile(filtered[i]),
      separatorBuilder: (_,__)=>(const SizedBox(height:12)),
      itemCount: filtered.length,
    );
  }

  Widget _cardTile(_AdminCard c){
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius:6, offset: const Offset(0,2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[
            CircleAvatar(
              radius:24,
              backgroundImage: (c.avatarUrl!=null && c.avatarUrl!.isNotEmpty) ? NetworkImage(c.avatarUrl!) : null,
              child: (c.avatarUrl==null || c.avatarUrl!.isEmpty) ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width:12),
            Expanded(child: Text(c.title, style: const TextStyle(fontSize:18, fontWeight: FontWeight.w700))),
            _statusBadge(c.status),
          ]),
          const SizedBox(height:8),
          Text(c.subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height:4),
          Text(c.line2, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
          const SizedBox(height:12),
          Row(children:[
            _actionBtn('Approuver', Colors.green.shade800, ()=>_approve(c.id)),
            const SizedBox(width:12),
            _actionBtn('Refuser', Colors.red.shade600, ()=>_reject(c.id)),
            const Spacer(),
            TextButton(onPressed: ()=>_block(c.id), child: const Text('Bloquer', style: TextStyle(color: Colors.red))),
          ]),
        ]),
      ),
    );
  }

  // UI helpers -------------
  Widget _pillButton({required String label, required bool active, required VoidCallback onTap}){
    return InkWell(
      onTap:onTap,
      child: Container(
        height:44, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E5631) : Colors.white,
          border: Border.all(color: const Color(0xFF1E5631)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(label, style: TextStyle(color: active?Colors.white:const Color(0xFF1E5631), fontWeight: FontWeight.w700, fontSize:16)),
      ),
    );
  }

  Widget _kpiCard({required String title, required String value}){
    return Container(
      width:170,
      padding: const EdgeInsets.symmetric(horizontal:14, vertical:14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black12, blurRadius:6, offset: const Offset(0,2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text(value, style: const TextStyle(fontSize:22, fontWeight: FontWeight.w800)),
        const SizedBox(height:4),
        Text(title, style: TextStyle(color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _statusBadge(String s){
    Color bg;
    switch(s){
      case 'approved': bg=Colors.green.shade100; break;
      case 'refused' : bg=Colors.red.shade100; break;
      case 'blocked' : bg=Colors.orange.shade100; break;
      default        : bg=Colors.grey.shade200; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:10, vertical:6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap){
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal:18, vertical:12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize:16, fontWeight: FontWeight.w700)),
    );
  }
}

class _AdminCard{
  final String id;
  final String title;
  final String subtitle;
  final String line2;
  final String status;
  final String? avatarUrl;
  final AdminTab kind;
  _AdminCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.line2,
    required this.status,
    required this.kind,
    this.avatarUrl,
  });
}
