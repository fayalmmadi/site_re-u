// lib/pages/owner_dashboard.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/voiture_selection.dart';
import 'driver_dashboard.dart';
import 'clients_page.dart';
import 'modifier_mot_de_passe_page.dart';
import 'modifier_voiture_page.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({Key? key}) : super(key: key);

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  int totalPassagers = 0;
  String debutJournee = '';
  String finJournee = '';
  List<Map<String, dynamic>> historiquePassagers = [];
  DateTime dateSelectionnee = DateTime.now();
  List<Map<String, dynamic>> voitures = [];

  // ---- Overlay langue ----
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  String langueActuelle = 'fr';

  // ---- Utils ----
  String? asUuid(String? v) => (v == null || v.trim().isEmpty) ? null : v;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revenirAujourdhui();
  }

  @override
  void initState() {
    super.initState();
    _chargerVoitures();
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
              offset: const Offset(0, 40),
              showWhenUnlinked: false,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _langueItem("Français", "fr"),
                      _langueItem("Anglais", "en"),
                      _langueItem("Comorien", "km"),
                      _langueItem("Arabe", "ar"),
                      _langueItem("Espagnol", "es"),
                      _langueItem("Chinois", "zh"),
                      _langueItem("Turc", "tr"),
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

  Widget _langueItem(String titre, String codeLangue) {
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

  // ---------- Navigation temporelle ----------
  void _revenirAujourdhui() {
    setState(() => dateSelectionnee = DateTime.now());
    _chargerNombrePassagers();
  }

  void _voirJourPrecedent() {
    setState(() => dateSelectionnee = dateSelectionnee.subtract(const Duration(days: 1)));
    _chargerNombrePassagers();
  }

  String _titreDateSelectionnee() {
    final now = DateTime.now();
    final dateActuelle = DateTime(now.year, now.month, now.day);
    final dateComparee = DateTime(dateSelectionnee.year, dateSelectionnee.month, dateSelectionnee.day);
    if (dateActuelle == dateComparee) return 'Aujourd’hui';

    const jours = ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];
    final jour = jours[dateSelectionnee.weekday - 1];
    final d = dateSelectionnee.day.toString().padLeft(2, '0');
    final m = dateSelectionnee.month.toString().padLeft(2, '0');
    final y = dateSelectionnee.year;
    return '$jour $d/$m/$y';
  }

  // ---------- Données ----------
  Future<void> _chargerVoitures() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final res = await Supabase.instance.client
        .from('voitures')
        .select()
        .eq('owner_user_id', userId);

    final list = (res as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    setState(() {
      voitures = list;
      if (VoitureSelection.voitureActuelle == null && voitures.isNotEmpty) {
        VoitureSelection.voitureActuelle = voitures.first;
      }
    });

    _chargerNombrePassagers();
  }

  Future<void> _chargerNombrePassagers() async {
    final date = '${dateSelectionnee.year}-${dateSelectionnee.month.toString().padLeft(2, '0')}-${dateSelectionnee.day.toString().padLeft(2, '0')}';

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Aucun utilisateur connecté');
      return;
    }

    final vId = asUuid(VoitureSelection.voitureActuelle?['id'] as String?);
    if (vId == null) {
      debugPrint('Aucune voiture sélectionnée');
      setState(() {
        totalPassagers = 0;
        historiquePassagers = [];
        debutJournee = '';
        finJournee = '';
      });
      return;
    }

    final rows = await Supabase.instance.client
        .from('passagers')
        .select('nombre_passagers, date, heure')
        .eq('date', date)
        .eq('voiture_id', vId)
        .order('heure', ascending: true);

    if (rows.isEmpty) {
      setState(() {
        totalPassagers = 0;
        historiquePassagers = [];
        debutJournee = '';
        finJournee = '';
      });
      return;
    }

    final data = rows.map((e) => Map<String, dynamic>.from(e)).toList();

    debutJournee = data.first['heure'].toString().substring(0, 5);
    finJournee = data.last['heure'].toString().substring(0, 5);

    int total = 0;
    final List<Map<String, dynamic>> histo = [];
    for (final row in data) {
      final count = (row['nombre_passagers'] ?? 0) as int;
      total += count;

      final raw = row['heure']?.toString() ?? '';
      final hhmm = raw.length >= 5 ? raw.substring(0, 5) : '??:??';

      histo.add({'heure': hhmm, 'nombre_passagers': count});
    }

    setState(() {
      totalPassagers = total;
      historiquePassagers = histo;
    });
  }

  // Chargement des voitures pour l’ExpansionTile
  Future<List<Map<String, dynamic>>> _loadMyCars() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final res = await Supabase.instance.client
        .from('voitures')
        .select()
        .eq('owner_user_id', uid);
    final list = (res as List?) ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final current = VoitureSelection.voitureActuelle ?? <String, dynamic>{};
    final titleCar = (current['display_driver_name']
            ?? current['nom']
            ?? current['immatriculation']
            ?? '')
        .toString();

    return Scaffold(
      // -------------- DRAWER --------------
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
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              final p = snapProfile.data ?? {};
              final prenom = (p['prenom'] ?? p['first_name'] ?? '').toString();
              final nom    = (p['nom'] ?? p['last_name']  ?? '').toString();
              final email  = (p['email'] ?? Supabase.instance.client.auth.currentUser?.email ?? '').toString();
              final initials = ((prenom.isNotEmpty ? prenom[0] : '') + (nom.isNotEmpty ? nom[0] : '')).toUpperCase();
              final fullName = ('$prenom $nom').trim();

              Future<void> _supprimerVoiture(String id) async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Supprimer cette voiture ?"),
                    content: const Text("Cette action est irréversible."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer")),
                    ],
                  ),
                );
                if (yes == true) {
                  await Supabase.instance.client.from('voitures').delete().eq('id', id);
                  await _chargerVoitures();
                }
              }

              return Column(
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(color: Color(0xFF084C28)),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Text(initials.isEmpty ? '??' : initials, style: const TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fullName.isEmpty ? '—' : fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              Text(email.isEmpty ? '—' : email, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                            final button = context.findRenderObject() as RenderBox;
                            final pos = button.localToGlobal(Offset.zero, ancestor: overlay);
                            await showMenu(
                              context: context,
                              position: RelativeRect.fromLTRB(
                                pos.dx, pos.dy + 40,
                                overlay.size.width - pos.dx - button.size.width, 0,
                              ),
                              items: [
                                PopupMenuItem(
                                  child: ListTile(leading: const Icon(Icons.language), title: Text('change_language'.tr())),
                                  onTap: () => Future.delayed(Duration.zero, _toggleLangueMenu),
                                ),
                                PopupMenuItem(
                                  child: ListTile(leading: const Icon(Icons.payment), title: Text('manage_subscription'.tr())),
                                  onTap: () => Future.delayed(Duration.zero, () => Navigator.pushNamed(context, '/abonnement')),
                                ),
                                PopupMenuItem(
                                  child: ListTile(leading: const Icon(Icons.directions_car), title: Text('add_car'.tr())),
                                  onTap: () => Future.delayed(Duration.zero, () => Navigator.pushNamed(context, '/ajouter-voiture')),
                                ),
                                PopupMenuItem(
                                  child: ListTile(leading: const Icon(Icons.lock), title: Text('password'.tr())),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ModifierMotDePassePage()));
                                  },
                                ),
                                PopupMenuItem(
                                  child: ListTile(leading: const Icon(Icons.logout), title: Text('logout'.tr())),
                                  onTap: () async {
                                    await Supabase.instance.client.auth.signOut();
                                    Future.delayed(Duration.zero, () => Navigator.pushReplacementNamed(context, '/login'));
                                  },
                                ),
                              ],
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.more_vert, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        ListTile(
                          title: Text('menu'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                        ),
                        const Divider(color: Colors.white),

                        ListTile(
                          leading: const Icon(Icons.directions_car, color: Colors.white),
                          title: Text('driver'.tr(), style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/chauffeur');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.person, color: Colors.white),
                          title: Text('owner'.tr(), style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/proprietaire');
                          },
                        ),

                        ExpansionTile(
                          iconColor: Colors.white,
                          collapsedIconColor: Colors.white,
                          title: Text("my_cars".tr(), style: const TextStyle(color: Colors.white)),
                          leading: const Icon(Icons.local_taxi, color: Colors.white),
                          children: [
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _loadMyCars(),
                              builder: (context, snapCars) {
                                if (snapCars.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                final items = snapCars.data ?? [];
                                if (items.isEmpty) {
                                  return const ListTile(
                                    title: Text("Aucune voiture ajoutée", style: TextStyle(color: Colors.white)),
                                  );
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const Divider(color: Colors.white24, height: 1),
                                  itemBuilder: (_, i) {
                                    final voiture = items[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        (voiture['display_driver_name'] ?? voiture['nom'] ?? 'Voiture inconnue').toString(),
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                      subtitle: Text(
                                        (voiture['immatriculation'] ?? '-').toString(),
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                      onTap: () {
                                        VoitureSelection.voitureActuelle = voiture;
                                        Navigator.pop(context);
                                        setState(() {});
                                        _chargerNombrePassagers();
                                      },
                                      trailing: PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: Colors.white),
                                        onSelected: (value) {
                                          if (value == 'modifier') {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ModifierVoiturePage(voiture: voiture),
                                              ),
                                            );
                                          } else if (value == 'supprimer') {
                                            _supprimerVoiture((voiture['id']).toString());
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                                          PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),

                        ListTile(
                          leading: const Icon(Icons.mail, color: Colors.yellow),
                          title: Text('contact_us'.tr(), style: const TextStyle(color: Colors.white)),
                          onTap: () => Navigator.pushNamed(context, '/contact'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.search, color: Colors.orange),
                          title: const Text("Chercher des clients", style: TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientsPage()));
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

      // -------------- APP BAR --------------
      appBar: AppBar(
        backgroundColor: const Color(0xFF084C28),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '$titleCar • ${'title'.tr()}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
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

      // -------------- BODY --------------
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Bloc profil/immat
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: Supabase.instance.client
                      .from('profiles')
                      .select()
                      .eq('id', Supabase.instance.client.auth.currentUser!.id)
                      .maybeSingle(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(height: 40, width: 40, child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const Text('—');
                    }

                    final profile = snapshot.data!;
                    final immat = (profile['immatriculation'] ?? '—').toString();
                    final prenom = (profile['prenom'] ?? profile['first_name'] ?? '').toString();
                    final nom    = (profile['nom'] ?? profile['last_name']  ?? '').toString();
                    final fullName = ('$prenom $nom').trim();

                    return Row(
                      children: [
                        const Icon(Icons.directions_car, size: 40, color: Colors.green),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(immat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(fullName, style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$totalPassagers Passagers', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_titreDateSelectionnee(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Début: $debutJournee'),
                      Text('Fin: $finJournee'),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SizedBox(
                  height: 120,
                  child: ListView.builder(
                    itemCount: historiquePassagers.length,
                    itemBuilder: (context, index) {
                      final entry = historiquePassagers[index];
                      final heure = entry['heure'];
                      final count = entry['nombre_passagers'];
                      final suffixe = count > 1 ? 'passagers' : 'passager';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Text('$heure  $count $suffixe'),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _voirJourPrecedent,
                child: Text('view_prev_month'.tr()),
              ),

              const SizedBox(height: 12),

              // --- Carte : suivi temps réel + polyline + multi-voitures ---
              OwnerLiveMap(
                selectedCar: VoitureSelection.voitureActuelle,
                ownerUserId: Supabase.instance.client.auth.currentUser?.id,
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF084C28),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () {
                  // TODO: export PDF
                },
                child: Text('export_pdf'.tr(), style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET : Carte temps réel propriétaire
// ─────────────────────────────────────────────────────────────────────────────

class OwnerLiveMap extends StatefulWidget {
  const OwnerLiveMap({
    super.key,
    required this.selectedCar,
    required this.ownerUserId,
  });

  final Map<String, dynamic>? selectedCar;
  final String? ownerUserId;

  @override
  State<OwnerLiveMap> createState() => _OwnerLiveMapState();
}

class _OwnerLiveMapState extends State<OwnerLiveMap> {
  GoogleMapController? _mapCtrl;

  // Modes d’affichage
  bool _multiView = false; // false = 1 voiture (polyline), true = toutes les voitures
  Duration _historySpan = const Duration(hours: 6); // fenêtre historique

  // Données carte
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng _lastCenter = const LatLng(0, 0);

  // Helpers coordonnées
  LatLng _posFrom(Map<String, dynamic> v) {
    // Supporte last_lat/last_lng ou latitude/longitude
    double _toD(dynamic x) {
      if (x == null) return 0;
      if (x is num) return x.toDouble();
      return double.tryParse(x.toString()) ?? 0;
    }

    final lat = _toD(v['last_lat'] ?? v['latitude']);
    final lng = _toD(v['last_lng'] ?? v['longitude']);
    return LatLng(lat, lng);
  }

  // ───────────────────────────────────────────
  // Streams
  // ───────────────────────────────────────────

  // 1) une seule voiture + polyline live
  Stream<Map<String, dynamic>?> _streamSingleCarRow(String carId) {
    return Supabase.instance.client
        .from('voitures')
        .stream(primaryKey: ['id'])
        .eq('id', carId)
        .limit(1)
        .map((rows) => rows.isEmpty ? null : Map<String, dynamic>.from(rows.first));
  }

  // 2) historique GPS (table: voiture_positions)
  // Schéma: id, voiture_id, lat, lng, ts (timestamp UTC)
  Stream<List<Map<String, dynamic>>> _streamCarHistory(String carId) async* {
    final stream = Supabase.instance.client
        .from('voiture_positions')
        .stream(primaryKey: ['id'])
        .eq('voiture_id', carId)
        .order('ts', ascending: true);

    await for (final rows in stream) {
      final since = DateTime.now().toUtc().subtract(_historySpan);
      final filtered = rows
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) {
            final t = DateTime.tryParse(e['ts'].toString()) ?? DateTime(1970);
            return t.isAfter(since);
          })
          .toList();
      yield filtered;
    }
  }

  // 3) toutes les voitures d’un propriétaire (pour la vue multi)
  Stream<List<Map<String, dynamic>>> _streamOwnerCars(String ownerUserId) {
    return Supabase.instance.client
        .from('voitures')
        .stream(primaryKey: ['id'])
        .eq('owner_user_id', ownerUserId)
        .map((rows) => rows
            .map((e) => Map<String, dynamic>.from(e))
            // filtre soft si coords nulles
            .where((v) {
              final p = _posFrom(v);
              return !(p.latitude == 0 && p.longitude == 0);
            })
            .toList());
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedCar;
    final ownerId = widget.ownerUserId;

    return Column(
      children: [
        // Barre d’actions carte
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('1 voiture'),
                selected: !_multiView,
                onSelected: (v) => setState(() => _multiView = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Toutes mes voitures'),
                selected: _multiView,
                onSelected: (v) => setState(() => _multiView = true),
              ),
              const Spacer(),
              if (!_multiView)
                DropdownButton<Duration>(
                  value: _historySpan,
                  onChanged: (d) => setState(() => _historySpan = d!),
                  items: const [
                    DropdownMenuItem(value: Duration(hours: 1),  child: Text('1 h')),
                    DropdownMenuItem(value: Duration(hours: 3),  child: Text('3 h')),
                    DropdownMenuItem(value: Duration(hours: 6),  child: Text('6 h')),
                    DropdownMenuItem(value: Duration(hours: 12), child: Text('12 h')),
                    DropdownMenuItem(value: Duration(days: 1),  child: Text('24 h')),
                  ],
                ),
            ],
          ),
        ),

        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 300,
            child: _multiView
                ? _buildMultiCars(ownerId)
                : _buildSingleCarWithPolyline(selected),
          ),
        ),
      ],
    );
  }

  // ── Mode 1 : une voiture + polyline
  Widget _buildSingleCarWithPolyline(Map<String, dynamic>? selectedCar) {
    final carId = (selectedCar?['id'] ?? '').toString();
    if (carId.isEmpty) {
      return const Center(child: Text('Aucune voiture sélectionnée'));
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _streamSingleCarRow(carId),
      builder: (context, carSnap) {
        if (carSnap.hasError) {
          return Center(child: Text('Erreur: ${carSnap.error}'));
        }
        if (!carSnap.hasData || carSnap.data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final car = carSnap.data!;
        final pos = _posFrom(car);

        _markers
          ..clear()
          ..add(Marker(
            markerId: const MarkerId('car'),
            position: pos,
            infoWindow: InfoWindow(
              title: (car['display_driver_name'] ?? car['nom'] ?? 'Ma voiture').toString(),
              snippet: '(${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})',
            ),
          ));

        if (_mapCtrl != null &&
            (pos.latitude != _lastCenter.latitude || pos.longitude != _lastCenter.longitude)) {
          _lastCenter = pos;
          _mapCtrl!.animateCamera(
            CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 15)),
          );
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streamCarHistory(carId),
          builder: (context, histSnap) {
            _polylines.clear();
            if (histSnap.hasData && histSnap.data!.isNotEmpty) {
              final pts = histSnap.data!
                  .map((e) => LatLng(
                        (e['lat'] as num).toDouble(),
                        (e['lng'] as num).toDouble(),
                      ))
                  .toList();

              _polylines.add(Polyline(
                polylineId: const PolylineId('history'),
                points: pts,
                width: 4,
                geodesic: true,
              ));
            }

            return GoogleMap(
              initialCameraPosition: CameraPosition(target: pos, zoom: 15),
              onMapCreated: (c) {
                _mapCtrl = c;
                _lastCenter = pos;
              },
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
            );
          },
        );
      },
    );
  }

  // ── Mode 2 : multi-voitures (toutes les voitures du propriétaire)
  Widget _buildMultiCars(String? ownerId) {
    if (ownerId == null || ownerId.isEmpty) {
      return const Center(child: Text('Aucun propriétaire connecté'));
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streamOwnerCars(ownerId),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
        final cars = snap.data ?? [];

        if (cars.isEmpty) {
          return const Center(child: Text('Aucune voiture trouvée'));
        }

        _markers.clear();
        for (final car in cars) {
          final pos = _posFrom(car);
          _markers.add(Marker(
            markerId: MarkerId('car_${car['id']}'),
            position: pos,
            infoWindow: InfoWindow(
              title: (car['display_driver_name'] ?? car['nom'] ?? 'Voiture').toString(),
              snippet: (car['immatriculation'] ?? '').toString(),
            ),
          ));
        }

        final firstPos = _posFrom(cars.first);
        return GoogleMap(
          initialCameraPosition: CameraPosition(target: firstPos, zoom: 12),
          onMapCreated: (c) {
            _mapCtrl = c;
            _lastCenter = firstPos;
          },
          markers: _markers,
          polylines: const <Polyline>{},
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapType: MapType.normal,
        );
      },
    );
  }
}
