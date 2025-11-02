// lib/scenes/driver_dashboard.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// PDF
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ✅ contrôle d’accès (3 essais / 2h puis blocage)
import '../utils/gate_feature.dart';

import 'package:suivi_taxis/widgets/objectif_du_jour.dart';
import '../controllers/voiture_selection.dart';
import 'qr_scanner_page.dart';
import 'stats_page.dart';
import 'clients_page.dart';
import 'modifier_voiture_page.dart';
import 'modifier_mot_de_passe_page.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  // ---- Nouveaux états de contrôle ----
  bool _ready = false; // évite d’afficher avant d’avoir résolu la voiture
  String? _selectedCarId; // id de la voiture sélectionnée

  int totalPassagers = 0;
  List<Map<String, dynamic>> historiquePassagers = [];
  DateTime dateSelectionnee = DateTime.now();

  // --- Abonnement ---
  DateTime? _validUntil; // date d’expiration d’abonnement (UTC -> local pour display)
  Timer? _subTimer; // rafraîchissement auto

  // --- Overlay Langue ---
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  String langueActuelle = 'fr';

  // --- Utils ---
  String? asUuid(String? v) => (v == null || v.trim().isEmpty) ? null : v;

  @override
  void initState() {
    super.initState();

    // 🔒 Garde d’auth : si pas connecté, redirige vers /login
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // Support des retours Web (magic link / reset)
      if (kIsWeb) {
        Future.microtask(() async {
          try {
            await Supabase.instance.client.auth
                .exchangeCodeForSession(Uri.base.toString());
          } catch (_) {}
        });
      }
      Future.microtask(() {
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: {'next': '/chauffeur'},
        );
      });
      return;
    }

    _boot();
  }

  @override
  void dispose() {
    _subTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await _ensureSelectedCar();
    await Future.wait([
      chargerNombrePassagers(),
      _loadSubscription(), // 🔔 lit subscriptions.valid_until
    ]);
    // rafraîchit toutes les 30s pour basculer automatiquement à l’expiration
    _subTimer?.cancel();
    _subTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadSubscription());

    if (!mounted) return;
    setState(() => _ready = true);
  }

  /// Lit la date d’expiration d’abonnement (table `subscriptions`)
  Future<void> _loadSubscription() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final row = await Supabase.instance.client
          .from('subscriptions')
          .select('valid_until')
          .eq('user_id', uid)
          .maybeSingle();

      final raw = row?['valid_until'];
      DateTime? v;
      if (raw != null) {
        v = DateTime.tryParse(raw.toString());
      }

      if (!mounted) return;
      setState(() => _validUntil = v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _validUntil = null);
    }
  }

  /// Garantit qu’une voiture est sélectionnée (mémoire globale + profil Supabase)
  Future<void> _ensureSelectedCar() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;

    // 1) si déjà en mémoire -> on persiste
    final memoryId = asUuid(VoitureSelection.voitureActuelle?['id'] as String?);
    if (memoryId != null) {
      _selectedCarId = memoryId;
      await supa
          .from('profiles')
          .update({'selected_voiture_id': memoryId}).eq('id', uid);
      return;
    }

    // 2) sinon, lire dans le profil
    final prof = await supa
        .from('profiles')
        .select('selected_voiture_id')
        .eq('id', uid)
        .maybeSingle();

    String? selected = prof?['selected_voiture_id'] as String?;

    // 3) si null -> première voiture
    if (selected == null) {
      final cars = await supa
          .from('voitures')
          .select(
              'id, immatriculation, display_driver_name, nom')
          .eq('owner_user_id', uid)
          .order('created_at')
          .limit(1);
      if (cars.isNotEmpty) {
        selected = cars.first['id'] as String;
        await supa
            .from('profiles')
            .update({'selected_voiture_id': selected}).eq('id', uid);
        VoitureSelection.voitureActuelle = cars.first;
      }
    } else {
      // hydrater VoitureSelection
      final car = await supa
          .from('voitures')
          .select(
              'id, immatriculation, display_driver_name, nom')
          .eq('id', selected)
          .maybeSingle();
      if (car != null) {
        VoitureSelection.voitureActuelle = car;
      }
    }

    _selectedCarId = selected;
  }

  // ---------- Overlay Langue ----------
  void _toggleLangueMenu() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    } else {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
        },
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _layerLink,
              offset: const Offset(-180, 40),
              showWhenUnlinked: false,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 200, maxWidth: 220),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      langueItem("Français", "fr"),
                      langueItem("Anglais", "en"),
                      langueItem("Comorien", "km"),
                      langueItem("Arabe", "ar"),
                      langueItem("Espagnol", "es"),
                      langueItem("Chinois", "zh"),
                      langueItem("Turc", "tr"),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget langueItem(String titre, String codeLangue) {
    return ListTile(
      title: Text(titre),
      onTap: () {
        context.setLocale(Locale(codeLangue));
        setState(() => langueActuelle = codeLangue);
        _overlayEntry?.remove();
        _overlayEntry = null;
      },
    );
  }

  // ---------- Données ----------
  Future<void> chargerNombrePassagers() async {
    final voitureId =
        _selectedCarId ?? asUuid(VoitureSelection.voitureActuelle?['id'] as String?);
    if (voitureId == null) return;

    final start = DateTime(dateSelectionnee.year, dateSelectionnee.month, 1);
    final next = DateTime(dateSelectionnee.year, dateSelectionnee.month + 1, 1);
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final nextStr = DateFormat('yyyy-MM-dd').format(next);

    final rows = await Supabase.instance.client
        .from('passagers')
        .select(
            'date, created_at, nombre_passagers')
        .eq('voiture_id', voitureId)
        .gte('date', startStr)
        .lt('date', nextStr)
        .order('date', ascending: true);

    int total = 0;
    final Map<String, int> histo = {};

    for (final row in rows) {
      final int n = (row['nombre_passagers'] as int?) ?? 0;
      String? d = row['date'] as String?;
      d ??= DateFormat('yyyy-MM-dd')
          .format(DateTime.parse(row['created_at'] as String).toLocal());
      histo[d] = (histo[d] ?? 0) + n;
      total += n;
    }

    final histoFormate = histo.entries
        .map((e) => {'date': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    setState(() {
      totalPassagers = total;
      historiquePassagers = histoFormate;
    });
  }

  Future<void> ajouterPassager(int nombre) async {
    final now = DateTime.now(); // local
    final date = DateFormat('yyyy-MM-dd').format(now);
    final heure = DateFormat('HH:mm:ss').format(now);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final voitureId =
        _selectedCarId ?? asUuid(VoitureSelection.voitureActuelle?['id'] as String?);
    if (voitureId == null) return;

    await Supabase.instance.client.from('passagers').insert({
      'voiture_id': voitureId,
      'chauffeur_id': user.id, // garde si la colonne existe
      'nombre_passagers': nombre,
      'date': date,
      'heure': heure,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Passager ajouté avec succès')),
    );

    await chargerNombrePassagers();
  }

  Future<List<Map<String, dynamic>>> loadMyCars() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final resp = await Supabase.instance.client
        .from('voitures')
        .select()
        .eq('owner_user_id', uid);
    return resp.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _supprimerVoiture(String id) async {
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer cette voiture ?"),
        content: const Text("Cette action est irréversible."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Supprimer")),
        ],
      ),
    );
    if (confirmation == true) {
      await Supabase.instance.client.from('voitures').delete().eq('id', id);
      if (_selectedCarId == id) {
        // si on supprime la voiture sélectionnée, on réinitialise proprement
        VoitureSelection.voitureActuelle = null;
        _selectedCarId = null;
        setState(() => _ready = false);
        await _ensureSelectedCar();
        await chargerNombrePassagers();
        if (mounted) setState(() => _ready = true);
      } else {
        setState(() {});
      }
    }
  }

  Future<void> onSelectCar(Map<String, dynamic> voiture) async {
    final carId = asUuid(voiture['id']?.toString());
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (carId == null || uid == null) return;

    await Supabase.instance.client
        .from('profiles')
        .update({'selected_voiture_id': carId}).eq('id', uid);

    VoitureSelection.voitureActuelle = voiture;
    setState(() => _selectedCarId = carId);
    await chargerNombrePassagers();
  }

  // ---------- Export PDF ----------
  Future<void> _exportPdf(BuildContext ctx) async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final dateHuman =
        DateFormat('EEEE dd MMMM yyyy', context.locale.toString()).format(now);

    final current = VoitureSelection.voitureActuelle ?? <String, dynamic>{};
    final titleCar =
        (current['display_driver_name'] ?? current['nom'] ?? current['immatriculation'] ?? '')
            .toString();
    final immat = (current['immatriculation'] ?? '').toString();

    // “Objectif du jour” facultatif
    String objectifJour = 'Non renseigné';
    try {
      final vId = _selectedCarId ?? asUuid(current['id']?.toString());
      if (vId != null) {
        final today = DateFormat('yyyy-MM-dd').format(now);
        final obj = await Supabase.instance.client
            .from('objectifs_du_jour')
            .select('objectif')
            .eq('voiture_id', vId)
            .eq('date', today)
            .maybeSingle();
        if (obj != null && obj['objectif'] != null) {
          objectifJour = obj['objectif'].toString();
        }
      }
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Rapport Chauffeur',
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Date : $dateHuman'),
          pw.Text('Voiture : $titleCar  •  Immatriculation : $immat'),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(width: 1),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total passagers du mois : $totalPassagers',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('Objectif du jour : $objectifJour'),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Historique (mois en cours)',
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (historiquePassagers.isEmpty)
            pw.Text('Aucune donnée pour le mois sélectionné.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Passagers'],
              data: historiquePassagers
                  .map((e) => [e['date'].toString(), e['count'].toString()])
                  .toList(),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  /// Petit bandeau d’état d’abonnement (actif / expiré)
  Widget _subscriptionBanner() {
    final now = DateTime.now();
    final isActive = _validUntil != null && _validUntil!.isAfter(now);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final txt = _validUntil != null ? fmt.format(_validUntil!.toLocal()) : null;

    Color bg = isActive ? Colors.green.shade100 : Colors.red.shade100;
    Color fg = isActive ? Colors.green.shade900 : Colors.red.shade900;
    String label = isActive
        ? '🔓 Abonnement actif jusqu’au : $txt'
        : (_validUntil == null
            ? '🔒 Aucun abonnement actif – mode démo (3 essais / 2h)'
            : '🔒 Abonnement expiré le : $txt – mode démo (3 essais / 2h)');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final current = VoitureSelection.voitureActuelle ?? <String, dynamic>{};
    final titleCar =
        (current['display_driver_name'] ?? current['nom'] ?? current['immatriculation'] ?? '')
            .toString();

    return Scaffold(
      drawer: Drawer(
        child: Container(
          color: const Color(0xFF084C28),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: Supabase.instance.client
                .from('profiles')
                .select()
                .eq('id', Supabase.instance.client.auth.currentUser!.id)
                .maybeSingle(),
            builder: (context, snapProfile) {
              if (snapProfile.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }

              final p = snapProfile.data ?? {};
              final prenom = (p['prenom'] ?? p['first_name'] ?? '').toString();
              final nom = (p['nom'] ?? p['last_name'] ?? '').toString();
              final email = (p['email'] ?? '').toString();
              final initials = ((prenom.isNotEmpty ? prenom[0] : '') +
                      (nom.isNotEmpty ? nom[0] : ''))
                  .toUpperCase();
              final fullName = ('$prenom $nom').trim();

              return Column(
                children: [
                  DrawerHeader(
                    decoration:
                        const BoxDecoration(color: Color(0xFF084C28)),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Text(initials.isEmpty ? '??' : initials,
                              style: const TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fullName.isEmpty ? '—' : fullName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              Text(email.isEmpty ? '—' : email,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final overlay = Overlay.of(context)
                                .context
                                .findRenderObject() as RenderBox;
                            final button =
                                context.findRenderObject() as RenderBox;
                            final pos = button.localToGlobal(Offset.zero,
                                ancestor: overlay);

                            await showMenu(
                              context: context,
                              position: RelativeRect.fromLTRB(
                                pos.dx,
                                pos.dy + 40,
                                overlay.size.width -
                                    pos.dx -
                                    button.size.width,
                                0,
                              ),
                              items: [
                                PopupMenuItem(
                                  child: ListTile(
                                    leading: const Icon(Icons.language),
                                    title: Text('change_language'.tr()),
                                  ),
                                  onTap: () => Future.delayed(
                                      Duration.zero, _toggleLangueMenu),
                                ),
                                PopupMenuItem(
                                  child: ListTile(
                                    leading: const Icon(Icons.payment),
                                    title: Text('manage_subscription'.tr()),
                                  ),
                                  onTap: () => Future.delayed(
                                    Duration.zero,
                                    () => Navigator.pushNamed(
                                        context, '/abonnement'),
                                  ),
                                ),
                                PopupMenuItem(
                                  child: ListTile(
                                    leading: const Icon(Icons.directions_car),
                                    title: Text('add_car'.tr()),
                                  ),
                                  onTap: () => Future.delayed(
                                    Duration.zero,
                                    () => Navigator.pushNamed(
                                        context, '/ajouter-voiture'),
                                  ),
                                ),
                                PopupMenuItem(
                                  child: ListTile(
                                    leading: const Icon(Icons.lock),
                                    title: Text('password'.tr()),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ModifierMotDePassePage(),
                                      ),
                                    );
                                  },
                                ),
                                PopupMenuItem(
                                  child: ListTile(
                                    leading: const Icon(Icons.logout),
                                    title: Text('logout'.tr()),
                                  ),
                                  onTap: () async {
                                    await Supabase.instance.client.auth
                                        .signOut();
                                    Future.delayed(
                                      Duration.zero,
                                      () => Navigator.pushReplacementNamed(
                                          context, '/login'),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child:
                                Icon(Icons.more_vert, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Menu latéral défilant
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        ListTile(
                          title: Text('menu'.tr(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20)),
                        ),
                        const Divider(color: Colors.white),

                        ListTile(
                          leading: const Icon(Icons.directions_car,
                              color: Colors.white),
                          title: Text('driver'.tr(),
                              style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/chauffeur');
                          },
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.person, color: Colors.white),
                          title: Text('owner'.tr(),
                              style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/proprietaire');
                          },
                        ),

                        ExpansionTile(
                          iconColor: Colors.white,
                          collapsedIconColor: Colors.white,
                          title: Text("my_cars".tr(),
                              style: const TextStyle(color: Colors.white)),
                          leading: const Icon(Icons.local_taxi,
                              color: Colors.white),
                          children: [
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: loadMyCars(),
                              builder: (context, snapCars) {
                                if (snapCars.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                        child:
                                            CircularProgressIndicator()),
                                  );
                                }
                                final items = snapCars.data ?? [];
                                if (items.isEmpty) {
                                  return const ListTile(
                                    title: Text("Aucune voiture ajoutée",
                                        style:
                                            TextStyle(color: Colors.white)),
                                  );
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(
                                          color: Colors.white24, height: 1),
                                  itemBuilder: (_, i) {
                                    final voiture = items[i];
                                    final isSelected = (_selectedCarId ?? '') ==
                                        (voiture['id']?.toString() ?? '');
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        (voiture['display_driver_name'] ??
                                                voiture['nom'] ??
                                                'Voiture inconnue')
                                            .toString(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                      subtitle: Text(
                                        (voiture['immatriculation'] ?? '-')
                                            .toString(),
                                        style: const TextStyle(
                                            color: Colors.white70),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isSelected)
                                            const Icon(Icons.check_circle,
                                                color:
                                                    Colors.lightGreenAccent),
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert,
                                                color: Colors.white),
                                            onSelected: (value) {
                                              if (value == 'modifier') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ModifierVoiturePage(
                                                            voiture:
                                                                voiture),
                                                  ),
                                                );
                                              } else if (value ==
                                                  'supprimer') {
                                                _supprimerVoiture(
                                                    voiture['id'] as String);
                                              }
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'modifier',
                                                  child: Text('Modifier')),
                                              PopupMenuItem(
                                                  value: 'supprimer',
                                                  child: Text('Supprimer')),
                                            ],
                                          ),
                                        ],
                                      ),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await onSelectCar(voiture);
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),

                        ListTile(
                          leading:
                              const Icon(Icons.mail, color: Colors.yellow),
                          title: Text('contact_us'.tr(),
                              style: const TextStyle(color: Colors.white)),
                          onTap: () =>
                              Navigator.pushNamed(context, '/contact'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.search,
                              color: Colors.orange),
                          title: const Text("Chercher des clients",
                              style: TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ClientsPage()));
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),

      appBar: AppBar(
        backgroundColor: const Color(0xFF084C28),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('$titleCar • ${'title'.tr()}',
            style: const TextStyle(color: Colors.white)),
        actions: [
          // Ancre du menu de langues
          CompositedTransformTarget(
            link: _layerLink,
            child: IconButton(
              tooltip: 'change_language'.tr(),
              icon: const Icon(Icons.language, color: Colors.white),
              onPressed: _toggleLangueMenu,
            ),
          ),
        ],
      ),

      // ⬇️ Body scrollable pour éviter tout overflow (mobile/web)
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                  // assure au moins la hauteur de l’écran, mais autorise le scroll si plus grand
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 🔔 Bandeau d'état d'abonnement
                    _subscriptionBanner(),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.yellow[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_taxi, size: 40),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('passenger_count'.tr(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text('$totalPassagers',
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ✅ Scanner QR protégé par gateFeature
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF084C28),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () async {
                        final ok = await gateFeature(context, 'scan_qr');
                        if (!ok) return;

                        final id =
                            _selectedCarId ?? VoitureSelection.voitureActuelle?['id'];
                        if (id == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QRCodePage(voitureId: id),
                          ),
                        );
                      },
                      child: Text('scan_qr'.tr(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(height: 12),

                    // ✅ Ajouter passager protégé par gateFeature
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF084C28),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () async {
                        final ok = await gateFeature(context, 'add_passenger');
                        if (!ok) return;

                        await ajouterPassager(1);
                      },
                      child: Text('add_passenger'.tr(),
                          style: const TextStyle(color: Colors.white)),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('history'.tr(),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF084C28),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const StatsPage()),
                            );
                          },
                          icon: const Icon(Icons.bar_chart, size: 18),
                          label: Text('statistics'.tr(),
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Historique + Objectif (responsive)
                    LayoutBuilder(
                      builder: (context, c) {
                        final isNarrow = c.maxWidth < 700;

                        final historique = Center(
                          child: SizedBox(
                            width: isNarrow ? double.infinity : 420,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 160,
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context)
                                          .copyWith(scrollbars: true),
                                      child: ListView.builder(
                                        itemCount: historiquePassagers.length,
                                        itemBuilder: (context, index) {
                                          final item =
                                              historiquePassagers[index];
                                          final date = item['date'];
                                          final count = item['count'];
                                          return Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 6),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14,
                                                horizontal: 20),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.grey
                                                      .withOpacity(0.3),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              '$date  passagers: $count',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextButton(
                                    onPressed: () async {
                                      setState(() {
                                        dateSelectionnee = DateTime(
                                          dateSelectionnee.year,
                                          dateSelectionnee.month - 1,
                                          1,
                                        );
                                      });
                                      await chargerNombrePassagers();
                                    },
                                    child: Text('view_prev_month'.tr(),
                                        style: const TextStyle(
                                            color: Colors.blue)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        final objectif = SizedBox(
                          width: isNarrow ? double.infinity : 280,
                          child: ObjectifDuJourCard(
                            voitureId: _selectedCarId ??
                                VoitureSelection.voitureActuelle?['id']
                                    as String?,
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              historique,
                              const SizedBox(height: 12),
                              objectif,
                            ],
                          );
                        } else {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Spacer(flex: 2),
                              historique,
                              const SizedBox(width: 24),
                              SizedBox(width: 280, child: objectif),
                              const Spacer(flex: 3),
                            ],
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 16),
                    // Bouton export en bas du scroll
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF084C28),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () => _exportPdf(context),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text('export_pdf'.tr(),
                          style: const TextStyle(color: Colors.white)),
                    ),

                    const SizedBox(height: 12), // petite marge bas
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
