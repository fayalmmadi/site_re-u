// lib/pages/demander_livraison_page.dart
// ======================================
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:country_picker/country_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

// données utilitaires (dossier data situé DANS pages)
import 'data/client_repository.dart';

// widgets/pages situés DANS pages
import 'widgets/courier_card.dart';
import 'accepted_list_page.dart';
import 'refused_list_page.dart';
import 'rejected_list_page.dart';
import 'pending_list_page.dart';

// ================== CONFIGURE ==================
// ⚠️ La key publique n'est plus utilisée côté client (toutes les requêtes Google passent par le proxy).
const String kGoogleApiKey = 'AIzaSyCIcG4XoPdxPU9b7ZSzZ3iOC6tB7aJshuc';

// Proxy Netlify (sécurise la clé serveur Google)
const String kPlacesProxyBase =
    'https://suivi-taxis.netlify.app/.netlify/functions/places_proxy';

// ================== Helpers devise =================
String _currencyCodeForIso(String iso) {
  switch (iso.toUpperCase()) {
    case 'KM':
      return 'KMF'; // Comores
    case 'MG':
      return 'MGA'; // Madagascar
    case 'SN':
    case 'BJ':
    case 'CI':
    case 'TG':
    case 'BF':
    case 'NE':
    case 'ML':
      return 'XOF'; // UEMOA
    case 'CM':
    case 'GA':
    case 'CG':
    case 'GQ':
    case 'TD':
    case 'CF':
      return 'XAF'; // CEMAC
    case 'US':
      return 'USD';
    case 'FR':
      return 'EUR';
    default:
      return 'EUR';
  }
}

String _currencySymbolForCode(String code) {
  switch (code.toUpperCase()) {
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
      return code;
  }
}

// ================== Helpers géo / Google APIs =================

// Token de session Google Places (safe Web/Mobile – corrige RangeError)
String _newPlacesSessionToken() {
  final rnd = Random();
  String hex(int bytes) =>
      List.generate(bytes, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
  return 'st-${DateTime.now().millisecondsSinceEpoch}-${hex(8)}';
}

(bool, double?, double?) _tryParseLatLng(String t) {
  final parts = t.split(',').map((s) => s.trim()).toList();
  if (parts.length == 2) {
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat != null && lng != null) return (true, lat, lng);
  }
  return (false, null, null);
}

// === Tous les appels Google passent par le proxy ===
Future<(double?, double?)> _geocodeAddress(String query) async {
  if (query.isEmpty) return (null, null);
  final uri = Uri.parse('$kPlacesProxyBase?endpoint=geocode&input=${Uri.encodeQueryComponent(query)}');
  final r = await http.get(uri);
  if (r.statusCode != 200) return (null, null);
  final data = json.decode(r.body);
  if ((data['status'] ?? '') != 'OK') return (null, null);
  final first = (data['results'] as List).first;
  final loc = first['geometry']['location'];
  return ((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
}

Future<List<Map<String, String>>> _placesAutocomplete(
  String input, {
  String? sessionToken,
}) async {
  if (input.trim().isEmpty) return [];
  final uri = Uri.parse('$kPlacesProxyBase'
      '?endpoint=autocomplete'
      '&input=${Uri.encodeQueryComponent(input)}'
      '&sessiontoken=${Uri.encodeQueryComponent(sessionToken ?? _newPlacesSessionToken())}');
  final r = await http.get(uri);
  if (r.statusCode != 200) return [];
  final data = json.decode(r.body);
  if ((data['status'] ?? '') != 'OK') return [];
  final preds = (data['predictions'] as List).cast<Map<String, dynamic>>();
  return preds
      .map((p) => {
            'place_id': p['place_id'] as String,
            'description': p['description'] as String,
          })
      .toList();
}

Future<(double?, double?)> _placeDetailsLatLng(
  String placeId, {
  String? sessionToken,
}) async {
  final uri = Uri.parse('$kPlacesProxyBase'
      '?endpoint=details'
      '&place_id=${Uri.encodeQueryComponent(placeId)}'
      '&sessiontoken=${Uri.encodeQueryComponent(sessionToken ?? _newPlacesSessionToken())}');
  final r = await http.get(uri);
  if (r.statusCode != 200) return (null, null);
  final data = json.decode(r.body);
  if ((data['status'] ?? '') != 'OK') return (null, null);
  final loc = data['result']['geometry']['location'];
  return ((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
}

// ====== ROUTE / DIRECTIONS ======
List<LatLng> _decodePolyline(String poly) {
  final List<LatLng> points = [];
  int index = 0, lat = 0, lng = 0;

  while (index < poly.length) {
    int b, shift = 0, result = 0;
    do {
      b = poly.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = poly.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

Set<Polyline> _polylines = {};

Future<void> _drawRoutePolyline({required double depLat, required double depLng, required double arrLat, required double arrLng, GoogleMapController? mapCtrl}) async {
  final uri = Uri.parse('$kPlacesProxyBase?endpoint=directions&origin=$depLat,$depLng&destination=$arrLat,$arrLng');
  final r = await http.get(uri);
  if (r.statusCode != 200) return;
  final data = json.decode(r.body);
  if ((data['status'] ?? '') != 'OK') return;

  final routes = (data['routes'] as List?);
  if (routes == null || routes.isEmpty) return;
  final poly = routes[0]['overview_polyline']?['points'] as String?;
  if (poly == null) return;

  final pts = _decodePolyline(poly);
  _polylines = {
    Polyline(
      polylineId: const PolylineId('route'),
      points: pts,
      width: 6,
      geodesic: true,
    )
  };

  if (mapCtrl != null && pts.isNotEmpty) {
    final sw = LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
      pts.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
    );
    final ne = LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
      pts.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
    );
    await mapCtrl.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 60),
    );
  }
}

// ===============================================================

class DemanderLivraisonPage extends StatefulWidget {
  const DemanderLivraisonPage({super.key});
  @override
  State<DemanderLivraisonPage> createState() => _DemanderLivraisonPageState();
}

class _DemanderLivraisonPageState extends State<DemanderLivraisonPage> {
  final supabase = Supabase.instance.client;
  final repo = ClientRepository();

  // recherche texte (type/zones/nom)
  final _searchCtrl = TextEditingController();
  final _categories = const ['Tout', 'Pizzerias', 'Meubles', 'Matériaux', 'Pharmacies'];
  String _selectedCategory = 'Tout';

  Map<String, dynamic>? _client;

  // Compteurs drawer
  int _countPending = 0;
  int _countAccepted = 0, _countRefused = 0, _countRejected = 0;

  // GPS / Nearby
  bool _useGps = false;
  bool _loadingNearby = false;
  Position? _pos;
  int _radiusMeters = 5000;
  final List<int> _radiusChoices = const [1000, 3000, 5000, 10000];
  List<Map<String, dynamic>> _nearbyLivreurs = [];

  // Barre unique + bottom-sheet (style Uber)
  final _departCtrl = TextEditingController();
  final _arriveeCtrl = TextEditingController();
  final _departFocus = FocusNode();
  final _arriveeFocus = FocusNode();
  double? _depLat, _depLng;
  double? _arrLat, _arrLng;

  // Autocomplete
  Timer? _debounce;
  String _placesSessionToken = _newPlacesSessionToken();
  List<Map<String, String>> _departSugg = [];
  List<Map<String, String>> _arriveeSugg = [];

  // Carte
  bool _showMap = true;
  GoogleMapController? _mapCtrl;
  final Set<Marker> _markers = {};
  final Map<String, Marker> _markersById = {}; // livreur_id -> Marker pour éviter le clignotement
  Timer? _liveTimer; // rafraîchissement périodique

  // Auto-search (itinéraire)
  bool _autoSearch = false;
  bool _loadingAuto = false;
  List<Map<String, dynamic>> _autoResults = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _departFocus.addListener(() => setState(() {}));
    _arriveeFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _searchCtrl.dispose();
    _departCtrl.dispose();
    _arriveeCtrl.dispose();
    _departFocus.dispose();
    _arriveeFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final cached = await repo.getFromCache();
    if (!mounted) return;
    setState(() => _client = cached);
    if (_client == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _ensureClientProfile();
        } catch (_) {}
      });
    } else {
      await _refreshCounts();
    }
  }

  // =================== COMPTEURS ===================
  Future<void> _refreshCounts() async {
    final cid = _client?['id'] as String?;
    if (cid == null) return;
    try {
      final p = await supabase
          .from('livraison_demandes')
          .select('id')
          .eq('client_id', cid)
          .eq('status', 'pending');

      final a = await supabase
          .from('livraison_demandes')
          .select('id')
          .eq('client_id', cid)
          .inFilter('status', ['accepted', 'accepted_by_driver'])
          .eq('client_seen_accepted', false);

      final r = await supabase
          .from('livraison_demandes')
          .select('id')
          .eq('client_id', cid)
          .inFilter('status', ['refused', 'refused_by_driver'])
          .eq('client_seen_refused', false);

      final c = await supabase
          .from('livraison_demandes')
          .select('id')
          .eq('client_id', cid)
          .inFilter('status', ['client_rejected', 'canceled_by_client'])
          .eq('client_seen_rejected', false);

      if (!mounted) return;
      setState(() {
        _countPending = (p as List).length;
        _countAccepted = (a as List).length;
        _countRefused = (r as List).length;
        _countRejected = (c as List).length;
      });
    } catch (e) {
      debugPrint('Erreur refreshCounts: $e');
    }
  }

  bool _matchFilters(Map<String, dynamic> l) {
    if ((l['est_valide'] ?? false) != true) return false;
    if ((l['est_bloque'] ?? false) == true) return false;

    final q = _searchCtrl.text.trim().toLowerCase();
    final type = (l['type_livraison'] ?? '').toString().toLowerCase();
    final zones = (l['zones'] ?? '').toString().toLowerCase();
    final nom = (l['nom'] ?? '').toString().toLowerCase();

    final cat = _selectedCategory.toLowerCase();
    final passCategory = (cat == 'tout') ? true : type.contains(cat);
    final passSearch = q.isEmpty || type.contains(q) || zones.contains(q) || nom.contains(q);
    return passCategory && passSearch;
  }

  Future<Map<String, dynamic>> _ensureClientProfile({String? prefillPhone}) async {
    if (_client != null && (_client!['id'] as String?) != null) return _client!;
    final res = await showModalBottomSheet<_QuickClientResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _QuickClientForm(prefillPhone: prefillPhone),
    );
    if (res == null) throw 'Inscription annulée';

    Map<String, dynamic> row;
    try {
      final inserted = await supabase.from('clients').insert({
        'nom': res.nom,
        'prenom': res.prenom,
        'phone': res.phone,
        'email': (res.email?.isEmpty ?? true) ? null : res.email,
        'pays': res.pays,
        'country_iso': res.countryIso,
        'phone_code': res.phoneCode,
      }).select().single();
      row = Map<String, dynamic>.from(inserted);
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('unique') || e.code == '23505') {
        final exist = await supabase
            .from('clients')
            .select()
            .or('phone.eq.${res.phone},email.eq.${res.email ?? ''}')
            .limit(1)
            .maybeSingle();
        if (exist == null) rethrow;
        row = Map<String, dynamic>.from(exist);
      } else {
        rethrow;
      }
    }

    final id = row['id'] as String;
    await repo.saveIdToCache(id);
    final fresh = await repo.reload(id);
    if (!mounted) return fresh;
    setState(() => _client = fresh);
    await _refreshCounts();
    return fresh;
  }

  // =================== GPS helpers ===================
  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await Geolocator.openLocationSettings();
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<void> _activateGpsAndLoadNearby() async {
    setState(() {
      _loadingNearby = true;
      _useGps = true;
      _nearbyLivreurs = [];
      _showMap = true;
    });
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) throw 'Permission localisation refusée.';
      _pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _loadNearby();
      await _moveMapTo(_pos!.latitude, _pos!.longitude, zoom: 13);

      // Live refresh (toutes les 6 s)
      _liveTimer?.cancel();
      _liveTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
        if (!mounted || !_useGps) return;
        await _loadNearby();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _useGps = false;
        _nearbyLivreurs = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Localisation impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  bool _listChanged(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final ia = a[i]['id'];
      final ib = b[i]['id'];
      if (ia != ib) return true;
    }
    return false;
  }

  Future<void> _loadNearby() async {
    if (_pos == null) return;
    setState(() => _loadingNearby = true);
    try {
      final rawDyn = await supabase.rpc('nearby_livreurs', params: {
        'lat': _pos!.latitude,
        'lng': _pos!.longitude,
        'radius_m': _radiusMeters,
        'limit_n': 50,
      });

      final raw = (rawDyn as List).cast<Map>();
      if (raw.isEmpty) {
        setState(() {
          _nearbyLivreurs = [];
          _markersById.clear();
          _markers.clear();
        });
        return;
      }

      final ids = raw.map((e) => e['livreur_id']).toList();
      final fullDyn = await supabase.from('livreurs').select().inFilter('id', ids);
      final full = (fullDyn as List).cast<Map<String, dynamic>>();

      final distById = {for (final e in raw) e['livreur_id']: e['distance_m']};
      final merged = full.map((x) {
        final m = Map<String, dynamic>.from(x);
        m['distance_m'] = distById[m['id']];
        return m;
      }).toList()
        ..sort((a, b) {
          final da = (a['distance_m'] ?? 0) as num;
          final db = (b['distance_m'] ?? 0) as num;
          return da.compareTo(db);
        });

      if (_listChanged(_nearbyLivreurs, merged)) {
        _nearbyLivreurs = merged;
      }
      _refreshMapMarkersFromList(merged); // mise à jour différentielle (no blink)
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur recherche à proximité : $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  // =================== “À la Uber” ===================
  Future<void> _useMyPositionAsDepart() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _depLat = pos.latitude;
      _depLng = pos.longitude;
      _departCtrl.text =
          'Ma position (${_depLat!.toStringAsFixed(5)}, ${_depLng!.toStringAsFixed(5)})';
      _departSugg = [];
    });
    await _moveMapTo(_depLat!, _depLng!, zoom: 14);
  }

  bool _coordsOk() => _depLat != null && _depLng != null && _arrLat != null && _arrLng != null;

  Future<void> _runAutoSearch() async {
    _placesSessionToken = _newPlacesSessionToken();

    Future<void> _ensureFieldLatLng(TextEditingController ctrl, bool isDepart) async {
      if ((isDepart ? _depLat : _arrLat) != null) return;
      final t = ctrl.text.trim();
      if (t.isEmpty) return;

      final parsed = _tryParseLatLng(t);
      if (parsed.$1) {
        setState(() {
          if (isDepart) {
            _depLat = parsed.$2;
            _depLng = parsed.$3;
          } else {
            _arrLat = parsed.$2;
            _arrLng = parsed.$3;
          }
        });
        return;
      }

      final (lat, lng) = await _geocodeAddress(t);
      setState(() {
        if (isDepart) {
          _depLat = lat;
          _depLng = lng;
        } else {
          _arrLat = lat;
          _arrLng = lng;
        }
      });
    }

    await _ensureFieldLatLng(_departCtrl, true);
    await _ensureFieldLatLng(_arriveeCtrl, false);

    if (!_coordsOk()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Définis départ et arrivée (adresse ou lat,lng).')),
      );
      return;
    }

    setState(() {
      _loadingAuto = true;
      _autoSearch = true;
      _autoResults = [];
      _showMap = true;
    });

    try {
      final rawDyn = await supabase.rpc('nearby_livreurs_with_estimate', params: {
        'p_pick_lat': _depLat,
        'p_pick_lng': _depLng,
        'p_drop_lat': _arrLat,
        'p_drop_lng': _arrLng,
        'p_radius_m': _radiusMeters,
        'p_limit_n': 50,
      });

      final raw = (rawDyn as List).cast<Map>();
      if (raw.isEmpty) {
        setState(() {
          _autoResults = [];
          _markersById.clear();
          _markers.clear();
          _polylines.clear();
        });
      } else {
        final ids = raw.map((e) => e['livreur_id']).toList();
        final fullDyn = await supabase.from('livreurs').select().inFilter('id', ids);
        final byId = {
          for (final e in (fullDyn as List).cast<Map<String, dynamic>>()) e['id']: e
        };

        final merged = <Map<String, dynamic>>[];
        for (final e in raw) {
          final id = e['livreur_id'];
          final base = byId[id];
          if (base != null) {
            final row = Map<String, dynamic>.from(base);
            row['distance_m'] = e['distance_m'];
            row['estimate_amount'] = e['estimate_amount'];
            row['estimate_currency'] = e['estimate_currency'];
            merged.add(row);
          }
        }

        merged.sort((a, b) {
          final ea = (a['estimate_amount'] ?? 1e12) as num;
          final eb = (b['estimate_amount'] ?? 1e12) as num;
          final cmp = ea.compareTo(eb);
          if (cmp != 0) return cmp;
          final da = (a['distance_m'] ?? 0) as num;
          final db = (b['distance_m'] ?? 0) as num;
          return da.compareTo(db);
        });

        setState(() => _autoResults = merged);
        _refreshMapMarkersFromList(merged);

        if (_depLat != null && _depLng != null && _arrLat != null && _arrLng != null) {
          await _drawRoutePolyline(
            depLat: _depLat!, depLng: _depLng!, arrLat: _arrLat!, arrLng: _arrLng!, mapCtrl: _mapCtrl,
          );
        }
      }

      if (_depLat != null && _depLng != null) {
        await _moveMapTo(_depLat!, _depLng!, zoom: 12);
      }

      // Live refresh pour l'itinéraire (6 s)
      _liveTimer?.cancel();
      _liveTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
        if (!mounted || !_autoSearch) return;
        await _runAutoSearch();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur recherche auto : $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingAuto = false);
    }
  }

  // ===== Autocomplete (live) =====
  void _onAddressChanged(bool isDepart, String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (value.trim().isEmpty) {
        setState(() {
          if (isDepart) {
            _departSugg = [];
          } else {
            _arriveeSugg = [];
          }
        });
        return;
      }
      final sugg = await _placesAutocomplete(value, sessionToken: _placesSessionToken);
      setState(() {
        if (isDepart) {
          _departSugg = sugg;
        } else {
          _arriveeSugg = sugg;
        }
      });
    });
  }

  Future<void> _selectPlaceSuggestion(bool isDepart, Map<String, String> item) async {
    final (lat, lng) =
        await _placeDetailsLatLng(item['place_id']!, sessionToken: _placesSessionToken);
    if (lat == null || lng == null) return;
    setState(() {
      if (isDepart) {
        _depLat = lat;
        _depLng = lng;
        _departCtrl.text = item['description']!;
        _departSugg = [];
      } else {
        _arrLat = lat;
        _arrLng = lng;
        _arriveeCtrl.text = item['description']!;
        _arriveeSugg = [];
      }
    });
    await _moveMapTo(lat, lng, zoom: 13);
  }

  // ===== Carte =====
  CameraPosition _initialCamera(String clientIso) {
    switch (clientIso.toUpperCase()) {
      case 'KM':
        return const CameraPosition(target: LatLng(-11.702, 43.255), zoom: 12);
      case 'FR':
        return const CameraPosition(target: LatLng(48.8566, 2.3522), zoom: 11);
      case 'MG':
        return const CameraPosition(target: LatLng(-18.8792, 47.5079), zoom: 12);
      default:
        return const CameraPosition(target: LatLng(0, 0), zoom: 2);
    }
  }

  Future<void> _moveMapTo(double lat, double lng, {double zoom = 14}) async {
    if (_mapCtrl == null) return;
    await _mapCtrl!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(lat, lng), zoom: zoom)),
    );
  }

  void _refreshMapMarkersFromList(List<Map<String, dynamic>> rows) {
    bool changed = false;
    final aliveIds = <String>{};

    for (final row in rows) {
      final id = (row['id'] ?? row['livreur_id']).toString();
      final lat = (row['last_lat'] ?? row['lat']) as num?;
      final lng = (row['last_lng'] ?? row['lng']) as num?;
      if (lat == null || lng == null) continue;
      aliveIds.add(id);

      final name = (row['nom'] ?? 'Livreur').toString();
      final distance = (row['distance_m'] as num?)?.toDouble();
      final snippet = (distance != null) ? 'À ${(distance / 1000).toStringAsFixed(1)} km' : '';

      final newMarker = Marker(
        markerId: MarkerId(id),
        position: LatLng(lat.toDouble(), lng.toDouble()),
        infoWindow: InfoWindow(title: name, snippet: snippet),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      );

      final old = _markersById[id];
      if (old == null ||
          old.position.latitude != newMarker.position.latitude ||
          old.position.longitude != newMarker.position.longitude ||
          old.infoWindow.title != newMarker.infoWindow.title) {
        _markersById[id] = newMarker;
        changed = true;
      }
    }

    // retire les livreurs disparus
    final toRemove = _markersById.keys.where((k) => !aliveIds.contains(k)).toList();
    if (toRemove.isNotEmpty) {
      for (final k in toRemove) {
        _markersById.remove(k);
      }
      changed = true;
    }

    if (changed) {
      _markers
        ..clear()
        ..addAll(_markersById.values);
    }
  }

  // ====== UI barre + bottom-sheet ======
  Future<void> _openPlanCourseSheet() async {
    if (_departCtrl.text.trim().isEmpty || _depLat == null || _depLng == null) {
      try {
        await _useMyPositionAsDepart();
      } catch (_) {}
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final pad = EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        );
        return SafeArea(
          child: Padding(
            padding: pad,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),

                // DEPART
                Column(
                  children: [
                    TextField(
                      controller: _departCtrl,
                      focusNode: _departFocus,
                      onChanged: (v) => _onAddressChanged(true, v),
                      decoration: InputDecoration(
                        labelText: 'Point de départ',
                        prefixIcon: const Icon(Icons.my_location),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _departCtrl.clear();
                            setState(() {
                              _depLat = _depLng = null;
                              _departSugg = [];
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onSubmitted: (_) {},
                    ),
                    if (_departFocus.hasFocus) _autocompleteList(true),
                  ],
                ),
                const SizedBox(height: 10),

                // ARRIVEE
                Column(
                  children: [
                    TextField(
                      controller: _arriveeCtrl,
                      focusNode: _arriveeFocus,
                      onChanged: (v) => _onAddressChanged(false, v),
                      decoration: InputDecoration(
                        labelText: 'Où allez-vous ?',
                        prefixIcon: const Icon(Icons.flag_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _arriveeCtrl.clear();
                            setState(() {
                              _arrLat = _arrLng = null;
                              _arriveeSugg = [];
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onSubmitted: (_) {},
                    ),
                    if (_arriveeFocus.hasFocus) _autocompleteList(false),
                  ],
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Chercher des livreurs'),
                    onPressed: _loadingAuto ? null : () async {
                      Navigator.pop(context);
                      await _runAutoSearch();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _whereToBar() {
    return InkWell(
      onTap: _openPlanCourseSheet,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _arriveeCtrl.text.trim().isEmpty
                    ? 'Où allez-vous ?'
                    : _arriveeCtrl.text.trim(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _openPlanCourseSheet,
              icon: const Icon(Icons.schedule, size: 16),
              label: const Text('Plus tard'),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Listes d’auto-complétion =====
  Widget _autocompleteList(bool isDepart) {
    final items = isDepart ? _departSugg : _arriveeSugg;
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final it = items[i];
          return ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(it['description'] ?? ''),
            onTap: () => _selectPlaceSuggestion(isDepart, it),
          );
        },
      ),
    );
  }

  // =================== UI app ===================
  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: const Color(0xFF22C55E),
      title: const Text('Demander une livraison',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      iconTheme: const IconThemeData(color: Colors.white),
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openEndDrawer(),
        ),
      ),
      actions: [
        IconButton(
          tooltip: _showMap ? 'Masquer la carte' : 'Afficher la carte',
          onPressed: () => setState(() => _showMap = !_showMap),
          icon: Icon(_showMap ? Icons.map_outlined : Icons.map),
          color: Colors.white,
        ),
      ],
    );
  }

  Drawer _endDrawer() {
    final email = (_client?['email'] ?? 'Email non renseigné').toString();
    final phone = (_client?['phone'] ?? '').toString();
    final nom = (_client?['nom'] ?? '').toString();
    final prenom = (_client?['prenom'] ?? '').toString();
    final displayName =
        (prenom.isNotEmpty || nom.isNotEmpty) ? '$prenom $nom'.trim() : 'Profil client';
    final photoUrl = (_client?['photo_url'] ?? '').toString();
    final cid = _client?['id'] as String?;

    String _maskPhone(String p) {
      final d = p.replaceAll(RegExp(r'\D'), '');
      if (d.isEmpty) return 'Téléphone non renseigné';
      if (d.length <= 4) return '••••';
      return '•••••••• ${d.substring(d.length - 4)}';
    }

    return Drawer(
      width: 310,
      elevation: 8,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF22C55E),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                    child: (photoUrl.isEmpty)
                        ? Text(
                            (displayName.isNotEmpty)
                                ? displayName
                                    .trim()
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .take(2)
                                    .map((s) => s[0].toUpperCase())
                                    .join()
                                : '??',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        Text(email, style: const TextStyle(color: Colors.white70)),
                        Text('Tel: ${_maskPhone(phone)}',
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_bottom),
              title: Text('En attente (${_countPending})'),
              onTap: () {
                Navigator.pop(context);
                if (cid != null) {
                  Navigator
                      .push(context,
                          MaterialPageRoute(builder: (_) => PendingListPage(clientId: cid)))
                      .then((_) => _refreshCounts());
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Compléter mon profil'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await _ensureClientProfile();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Profil à jour ✅')));
                } catch (_) {}
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text('Demandes acceptées (${_countAccepted})'),
              onTap: () {
                Navigator.pop(context);
                if (cid != null) {
                  Navigator
                      .push(context,
                          MaterialPageRoute(builder: (_) => AcceptedListPage(clientId: cid)))
                      .then((_) => _refreshCounts());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: Text('Demandes refusées (${_countRefused})'),
              onTap: () {
                Navigator.pop(context);
                if (cid != null) {
                  Navigator
                      .push(context,
                          MaterialPageRoute(builder: (_) => RefusedListPage(clientId: cid)))
                      .then((_) => _refreshCounts());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.not_interested_outlined),
              title: Text("Rejets d'acceptation (${_countRejected})"),
              onTap: () {
                Navigator.pop(context);
                if (cid != null) {
                  Navigator
                      .push(context,
                          MaterialPageRoute(builder: (_) => RejectedListPage(clientId: cid)))
                      .then((_) => _refreshCounts());
                }
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Déconnexion'),
              onTap: () async {
                await repo.saveIdToCache(''); // “déconnecte” le profil client local
                if (!mounted) return;
                setState(() {
                  _client = null;
                  _countPending = _countAccepted = _countRefused = _countRejected = 0;
                });
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    await _ensureClientProfile();
                  } catch (_) {}
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sidePad = EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width < 600 ? 12 : 24,
    );

    final _clientIso = ((_client?['country_iso'] ?? '') as String).toUpperCase();
    final _clientCountry = (_client?['pays'] ?? '').toString();

    final _clientCurrencyCode =
        _currencyCodeForIso(_clientIso.isEmpty ? 'FR' : _clientIso);
    final _clientCurrencySymb = _currencySymbolForCode(_clientCurrencyCode);

    final initialCam = _depLat != null && _depLng != null
        ? CameraPosition(target: LatLng(_depLat!, _depLng!), zoom: 13)
        : _initialCamera(_clientIso.isEmpty ? 'FR' : _clientIso);

    return Scaffold(
      appBar: _appBar(),
      endDrawer: _endDrawer(),
      body: Column(
        children: [
          // Barre “Où allez-vous ?”
          Padding(
            padding: sidePad.copyWith(top: 10, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _whereToBar(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _useMyPositionAsDepart,
                  icon: const Icon(Icons.gps_fixed, size: 18),
                  label: const Text('Définir “Ma position” comme départ'),
                ),
              ],
            ),
          ),

          // Carte
          if (_showMap)
            Padding(
              padding: sidePad.copyWith(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 260,
                  child: GoogleMap(
                    initialCameraPosition: initialCam,
                    onMapCreated: (c) => _mapCtrl = c,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    markers: _markers, // voitures affichées ici (no blink)
                    polylines: _polylines, // ligne d'itinéraire
                  ),
                ),
              ),
            ),

          // Recherche texte + GPS
          Padding(
            padding: sidePad.copyWith(top: 8, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'camion, pizza, ciment…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _useGps
                    ? OutlinedButton.icon(
                        onPressed: () {
                          _liveTimer?.cancel();
                          setState(() {
                            _useGps = false;
                            _nearbyLivreurs = [];
                            _markersById.clear();
                            _markers.clear();
                          });
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Effacer'),
                      )
                    : ElevatedButton.icon(
                        onPressed: _loadingNearby ? null : _activateGpsAndLoadNearby,
                        icon: const Icon(Icons.my_location),
                        label: const Text('Utiliser ma position'),
                      ),
              ],
            ),
          ),

          // Catégories
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: sidePad,
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) {
                final label = _categories[i];
                final sel = label == _selectedCategory;
                return ChoiceChip(
                  label: Text(
                    label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.black),
                  ),
                  selected: sel,
                  selectedColor: const Color(0xFF22C55E),
                  onSelected: (_) => setState(() => _selectedCategory = label),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _categories.length,
            ),
          ),

          const SizedBox(height: 4),

          if (_client == null)
            Expanded(
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await _ensureClientProfile();
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Créer mon profil pour voir les livreurs'),
                ),
              ),
            )
          else if (_autoSearch)
            // Résultats itinéraire (triés par prix/distance)
            Expanded(
              child: _loadingAuto
                  ? const Center(child: CircularProgressIndicator())
                  : (_autoResults.isEmpty)
                      ? const Center(child: Text('Aucun livreur trouvé pour cet itinéraire.'))
                      : ListView.separated(
                          padding: sidePad.copyWith(bottom: 16),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemCount: _autoResults.length,
                          itemBuilder: (_, i) {
                            final row = _autoResults[i];
                            if (!_matchFilters(row)) return const SizedBox.shrink();
                            return CourierCard(
                              livreur: row,
                              clientCountryIso: _clientIso,
                              clientCurrencyCode: _clientCurrencyCode,
                              clientCurrencySymbol: _clientCurrencySymb,
                              onEnsureClient: _ensureClientProfile,
                              onAfterRequest: () async => _refreshCounts(),
                            );
                          },
                        ),
            )
          else if (_useGps)
            // À proximité (GPS)
            Expanded(
              child: _loadingNearby
                  ? const Center(child: CircularProgressIndicator())
                  : (_nearbyLivreurs.isEmpty)
                      ? const Center(child: Text('Aucun livreur à proximité.'))
                      : Column(
                          children: [
                            Padding(
                              padding: sidePad.copyWith(top: 6, bottom: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.place_outlined, size: 18),
                                  const SizedBox(width: 6),
                                  const Text('Rayon :'),
                                  const SizedBox(width: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: _radiusChoices.map((m) {
                                      final sel = m == _radiusMeters;
                                      final km = m >= 1000
                                          ? (m / 1000).toStringAsFixed(0)
                                          : m.toString();
                                      final unit = m >= 1000 ? ' km' : ' m';
                                      return ChoiceChip(
                                        label: Text(
                                          '$km$unit',
                                          style: TextStyle(
                                              color: sel ? Colors.white : Colors.black),
                                        ),
                                        selected: sel,
                                        selectedColor: const Color(0xFF22C55E),
                                        onSelected: (_) async {
                                          setState(() => _radiusMeters = m);
                                          await _loadNearby();
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: sidePad.copyWith(bottom: 16),
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemCount: _nearbyLivreurs.length,
                                itemBuilder: (_, i) {
                                  final row = _nearbyLivreurs[i];
                                  if (!_matchFilters(row)) return const SizedBox.shrink();
                                  return CourierCard(
                                    livreur: row,
                                    clientCountryIso: _clientIso,
                                    clientCurrencyCode: _clientCurrencyCode,
                                    clientCurrencySymbol: _clientCurrencySymb,
                                    onEnsureClient: _ensureClientProfile,
                                    onAfterRequest: () async => _refreshCounts(),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
            )
          else
            // Fallback par pays (stream)
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                key: ValueKey('livreurs-${_clientIso.isNotEmpty ? _clientIso : _clientCountry}'),
                stream: supabase
                    .from('livreurs')
                    .stream(primaryKey: ['id'])
                    .eq(_clientIso.isNotEmpty ? 'country_iso' : 'pays',
                        _clientIso.isNotEmpty ? _clientIso : _clientCountry)
                    .order('is_online', ascending: false)
                    .order('last_seen_at', ascending: false),
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Erreur: ${snap.error}'));
                  }

                  final rows = (snap.data ?? []).where(_matchFilters).toList();
                  if (rows.isEmpty) {
                    return const Center(child: Text('Aucun livreur trouvé pour ce pays.'));
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _refreshMapMarkersFromList(rows); // affiche / met à jour les voitures
                    setState(() {});
                  });

                  return ListView.separated(
                    padding: sidePad.copyWith(bottom: 16),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => CourierCard(
                      livreur: rows[i],
                      clientCountryIso: _clientIso,
                      clientCurrencyCode: _clientCurrencyCode,
                      clientCurrencySymbol: _clientCurrencySymb,
                      onEnsureClient: _ensureClientProfile,
                      onAfterRequest: () async => _refreshCounts(),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/* -------------------- Mini formulaire profil client -------------------- */

class _QuickClientResult {
  final String nom, prenom, phone, pays, countryIso, phoneCode;
  final String? email;
  _QuickClientResult({
    required this.nom,
    required this.prenom,
    required this.phone,
    required this.pays,
    required this.countryIso,
    required this.phoneCode,
    this.email,
  });
}

class _QuickClientForm extends StatefulWidget {
  const _QuickClientForm({this.prefillPhone});
  final String? prefillPhone;

  @override
  State<_QuickClientForm> createState() => _QuickClientFormState();
}

class _QuickClientFormState extends State<_QuickClientForm> {
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  Country _country = CountryParser.parseCountryCode('KM'); // par défaut

  String _localPart(String t) => t.trim().replaceFirst(RegExp(r'^\+\d+\s*'), '');
  String _digitsOnly(String t) => t.replaceAll(RegExp(r'\D'), '');

  String _buildE164() {
    var local = _digitsOnly(_phone.text.trim());
    local = local.replaceFirst(RegExp(r'^0+'), '');
    return '+${_country.phoneCode}$local';
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (c) => setState(() => _country = c),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.prefillPhone != null && widget.prefillPhone!.isNotEmpty) {
      _phone.text = _localPart(widget.prefillPhone!);
    }
    _phone.addListener(() {
      final t = _phone.text;
      final local = _localPart(t);
      if (t != local) {
        final digits = _digitsOnly(local);
        _phone.value = TextEditingValue(
          text: digits,
          selection: TextSelection.collapsed(offset: digits.length),
        );
      }
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Créer / mettre à jour votre profil',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickCountry,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration:
                    const InputDecoration(labelText: 'Pays', border: OutlineInputBorder()),
                child: Row(
                  children: [
                    Text(_country.flagEmoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('${_country.name} (+${_country.phoneCode})',
                            overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.keyboard_arrow_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _prenom,
                    decoration:
                        const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nom,
                    decoration:
                        const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: InputDecoration(
                labelText: 'Téléphone',
                border: const OutlineInputBorder(),
                prefixText: '${_country.flagEmoji} +${_country.phoneCode} ',
                prefixStyle: const TextStyle(fontWeight: FontWeight.w600),
                hintText: 'ex: 612345678',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email (facultatif)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_nom.text.trim().isEmpty ||
                      _prenom.text.trim().isEmpty ||
                      _phone.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Nom, prénom et téléphone sont requis.')));
                    return;
                  }
                  final fullPhone = _buildE164();
                  Navigator.pop(
                    context,
                    _QuickClientResult(
                      nom: _nom.text.trim(),
                      prenom: _prenom.text.trim(),
                      phone: fullPhone,
                      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
                      pays: _country.name,
                      countryIso: _country.countryCode,
                      phoneCode: _country.phoneCode,
                    ),
                  );
                },
                child: const Text('Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
