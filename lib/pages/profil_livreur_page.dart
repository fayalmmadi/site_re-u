// lib/pages/profil_livreur_page.dart
import 'dart:typed_data';
import 'dart:async'; // ← ajout
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:country_picker/country_picker.dart';
import 'package:geolocator/geolocator.dart'; // ← ajout

/// ───────────────────────────────────────────────────────────
/// 1) Modèle KYC par pays (style partenaire)
/// ───────────────────────────────────────────────────────────
enum KycLevel { minimum, enhanced, financial }

enum DriverDocType {
  nationalIdFront,     // CNI recto
  nationalIdBack,      // CNI verso
  selfie,              // selfie anti-fraude
  driverLicense,       // permis
  vehicleRegistration, // carte grise
  vehicleInsurance,    // assurance
  proofOfAddress,      // justificatif de domicile (<3 mois)
  iban,                // IBAN / RIB (paiements)
  businessStatus,      // SIREN/SIRET/NIF/UTR...
  companyExtract,      // KBIS/RC/Companies House extract
}

@immutable
class DriverRequirement {
  final KycLevel level;
  final Set<DriverDocType> requiredDocs;
  final List<String> hints;
  const DriverRequirement({
    required this.level,
    required this.requiredDocs,
    this.hints = const [],
  });

  bool get needsIdFront => requiredDocs.contains(DriverDocType.nationalIdFront);
  bool get needsIdBack  => requiredDocs.contains(DriverDocType.nationalIdBack);
  bool get needsSelfie  => requiredDocs.contains(DriverDocType.selfie);
  bool get needsLicense => requiredDocs.contains(DriverDocType.driverLicense);
  bool get needsReg     => requiredDocs.contains(DriverDocType.vehicleRegistration);
  bool get needsIns     => requiredDocs.contains(DriverDocType.vehicleInsurance);
  bool get needsPoA     => requiredDocs.contains(DriverDocType.proofOfAddress);
  bool get needsIban    => requiredDocs.contains(DriverDocType.iban);
  bool get needsBiz     => requiredDocs.contains(DriverDocType.businessStatus);
  bool get needsKbis    => requiredDocs.contains(DriverDocType.companyExtract);
}

const _defaultDriverReq = DriverRequirement(
  level: KycLevel.minimum,
  requiredDocs: {
    DriverDocType.nationalIdFront,
    DriverDocType.nationalIdBack,
    DriverDocType.selfie,
    DriverDocType.driverLicense,
    DriverDocType.vehicleRegistration,
    DriverDocType.vehicleInsurance,
  },
  hints: ["KYC minimum livreur : CNI (recto/verso), Permis, Carte grise, Assurance, Selfie."],
);

final Map<String, DriverRequirement> driverKycByCountry = {
  // Afrique
  'KM': _defaultDriverReq, 'MG': _defaultDriverReq, 'CM': _defaultDriverReq,
  'SN': _defaultDriverReq, 'CI': _defaultDriverReq, 'MA': _defaultDriverReq, 'TN': _defaultDriverReq,
  // Europe / UK
  'FR': DriverRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
      DriverDocType.companyExtract,
    },
    hints: ["FR : SIREN/SIRET si indépendant ; KBIS si société.", "IBAN et justificatif de domicile requis."],
  ),
  'BE': DriverRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
    },
    hints: ["BE : numéro d’entreprise & IBAN requis si indépendant."],
  ),
  'ES': DriverRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
    },
    hints: ["ES : NIE/CIF selon statut."],
  ),
  'IT': DriverRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
    },
    hints: ["IT : Partita IVA si professionnel."],
  ),
  'GB': DriverRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
      DriverDocType.companyExtract,
    },
    hints: ["UK : Companies House/UTR selon statut."],
  ),
  // Amériques
  'US': DriverRequirement(
    level: KycLevel.financial,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
    },
    hints: ["US : EIN/SSN/ITIN selon statut."],
  ),
  'CA': DriverRequirement(
    level: KycLevel.financial,
    requiredDocs: {
      DriverDocType.nationalIdFront, DriverDocType.nationalIdBack, DriverDocType.selfie,
      DriverDocType.driverLicense, DriverDocType.vehicleRegistration, DriverDocType.vehicleInsurance,
      DriverDocType.proofOfAddress, DriverDocType.iban, DriverDocType.businessStatus,
    },
    hints: ["CA : NE & exigences FINTRAC si financier."],
  ),
};

DriverRequirement driverReqForCountry(String? iso2) {
  if (iso2 == null || iso2.isEmpty) return _defaultDriverReq;
  return driverKycByCountry[iso2.toUpperCase()] ?? _defaultDriverReq;
}

/// ───────────────────────────────────────────────────────────
/// 2) Page Profil Livreur
/// ───────────────────────────────────────────────────────────
class ProfilLivreurPage extends StatefulWidget {
  const ProfilLivreurPage({super.key});
  @override
  State<ProfilLivreurPage> createState() => _ProfilLivreurPageState();
}

class _ProfilLivreurPageState extends State<ProfilLivreurPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Champs texte
  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _zonesCtrl = TextEditingController();
  final _prixCtrl = TextEditingController();

  final _phoneFocus = FocusNode();

  // Pays + devise
  Country? _country;
  String? _currencyCode;
  String get _dial => _country?.phoneCode ?? '';

  // KYC dynamique
  DriverRequirement _req = _defaultDriverReq;
  final Map<String, dynamic> _docsToUpload = {}; // {key:{url,status}}

  // Type de livraison
  final List<String> _types = const [
    'Livraison tout type', 'Pizzerias', 'Meubles', 'Matériaux', 'Pharmacies',
  ];
  String _typeSelected = 'Livraison tout type';

  bool _negociable = true;
  bool _pro = false;

  // Photos véhicule
  Uint8List? _p1Bytes;
  Uint8List? _p2Bytes;
  String? _p1Url;
  String? _p2Url;

  bool _loading = false;
  bool _checking = true;

  // Téléphone (longueurs locales)
  static const Map<String, int> _nationalLen = {
    'KM': 7, 'MG': 9, 'CM': 9, 'SN': 9, 'CI': 8, 'MA': 9, 'TN': 8,
    'FR': 9, 'BE': 9, 'ES': 9, 'IT': 9, 'GB': 10,
    'US': 10, 'CA': 10,
  };

  // Fallback devise par ISO2
  static const Map<String, String> _isoToCurrency = {
    'KM': 'KMF', 'MG': 'MGA', 'SN': 'XOF', 'CM': 'XAF', 'CI': 'XOF', 'MA': 'MAD', 'TN': 'TND',
    'FR': 'EUR', 'BE': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'DE': 'EUR', 'PT': 'EUR', 'IE': 'EUR',
    'GB': 'GBP', 'CH': 'CHF', 'PL': 'PLN', 'RO': 'RON', 'SE': 'SEK', 'NO': 'NOK',
    'US': 'USD', 'CA': 'CAD', 'JP': 'JPY',
  };

  // ⚠️ bien échapper le $
static const Map<String, String> _currencySymbol = {
  'EUR': '€',
  'USD': r'\$',   // ou '\$'
  'GBP': '£',
  'CHF': 'CHF',
  'KMF': 'KMF',
  'MGA': 'Ar',
  'XOF': 'F CFA',
  'XAF': 'F CFA',
  'MAD': 'MAD',
  'TND': 'TND',
  'CAD': 'C\$',   // <<< ICI l’erreur la plus fréquente
  'JPY': '¥',
};

  String _symbolFor(String? code) => _currencySymbol[code] ?? (code ?? '');

  // ── Ajouts GPS temps réel ─────────────────────────────────
  Timer? _gpsTimer;
  bool _shareLive = false;       // switch “Temps réel”
  DateTime? _lastGpsAt;          // dernier envoi
  // ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  @override
  void dispose() {
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _phoneCtrl.dispose();
    _zonesCtrl.dispose();
    _prixCtrl.dispose();
    _phoneFocus.dispose();
    _gpsTimer?.cancel(); // ← nettoyage timer
    super.dispose();
  }

  // -------- Vérifie si un profil existe déjà --------
  Future<void> _checkExisting() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        setState(() => _checking = false);
        return;
      }
      final row = await supabase
          .from('livreurs')
          .select('id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        Navigator.pushReplacementNamed(context, '/livreur_statut');
      } else {
        setState(() => _checking = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  // -------- Sélection pays : charge devise depuis DB (fallback local) + KYC --------
  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (c) async {
        final baseReq = driverReqForCountry(c.countryCode);

        String? dbCurrency;
        try {
          final row = await supabase
              .from('country_defaults')
              .select('currency_code')
              .eq('country', c.countryCode)
              .maybeSingle();
          dbCurrency = row?['currency_code'] as String?;
        } catch (_) {
          dbCurrency = null;
        }

        final currency = dbCurrency ?? _isoToCurrency[c.countryCode] ?? 'EUR';

        if (!mounted) return;
        setState(() {
          _country = c;
          _currencyCode = currency;
          _req = baseReq;
          _docsToUpload.clear();
          _phoneCtrl.text = _digitsOnly(_localFromAny(_phoneCtrl.text));
        });

        await Future.delayed(const Duration(milliseconds: 120));
        if (mounted) FocusScope.of(context).requestFocus(_phoneFocus);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pays : ${c.name} – Devise : $_currencyCode')),
          );
        }
      },
    );
  }

  // -------- Utils téléphone --------
  String _digitsOnly(String t) => t.replaceAll(RegExp(r'\D'), '');
  String _localFromAny(String t) => t.trim().replaceFirst(RegExp(r'^\+\d+\s*'), '');

  String _buildE164() {
    if (_country == null) return '';
    var local = _digitsOnly(_phoneCtrl.text.trim());
    local = local.replaceFirst(RegExp(r'^0+'), '');
    return '+${_country!.phoneCode}$local';
  }

  String? _validatePhone(String? value) {
    if (_country == null) return 'Choisis d’abord un pays';
    final digits = _digitsOnly(value ?? '');
    if (digits.isEmpty) return 'Numéro obligatoire';
    final expected = _nationalLen[_country!.countryCode];
    if (expected != null && digits.length != expected) {
      return 'Numéro incompatible avec ${_country!.name} (attendu: $expected chiffres)';
    }
    if (expected == null && (digits.length < 6 || digits.length > 12)) {
      return 'Longueur du numéro invalide';
    }
    return null;
  }

  // -------- Uploads --------
  Future<void> _pickImage({required int idx}) async {
    try {
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (res != null && res.files.single.bytes != null) {
          setState(() {
            if (idx == 1) _p1Bytes = res.files.single.bytes!;
            if (idx == 2) _p2Bytes = res.files.single.bytes!;
          });
        }
      } else {
        final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
        if (img != null) {
          final bytes = await img.readAsBytes();
          setState(() {
            if (idx == 1) _p1Bytes = bytes;
            if (idx == 2) _p2Bytes = bytes;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload image : $e')));
    }
  }

  Future<String?> _uploadVeh(Uint8List bytes, String key) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'Utilisateur non connecté';
      final objectKey = '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$key.jpg';
      await supabase.storage.from('vehicules').uploadBinary(
        objectKey, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
      );
      return supabase.storage.from('vehicules').getPublicUrl(objectKey);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload échoué : $e')));
      return null;
    }
  }

  Future<String?> _uploadDoc(Uint8List bytes, String key) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'Utilisateur non connecté';
      final objectKey = '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$key';
      await supabase.storage.from('livreurs-docs').uploadBinary(
        objectKey, bytes, fileOptions: const FileOptions(upsert: true),
      );
      return supabase.storage.from('livreurs-docs').getPublicUrl(objectKey);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import doc : $e')));
      return null;
    }
  }

  Future<void> _pickAndStoreDoc(String docKey, {bool pdfAllowed = false}) async {
    try {
      Uint8List? bytes;
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          type: pdfAllowed ? FileType.custom : FileType.image,
          allowedExtensions: pdfAllowed ? ['pdf', 'jpg', 'jpeg', 'png'] : null,
          withData: true,
        );
        bytes = res?.files.single.bytes;
      } else {
        if (pdfAllowed) {
          final res = await FilePicker.platform.pickFiles(
            type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png'], withData: true);
          bytes = res?.files.single.bytes;
        } else {
          final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
          bytes = img == null ? null : await img.readAsBytes();
        }
      }
      if (bytes == null) return;

      final url = await _uploadDoc(bytes, docKey);
      if (url == null) return;

      setState(() {
        _docsToUpload[docKey] = {'url': url, 'status': 'uploaded'};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import document : $e')));
    }
  }

  // -------- UI checklist KYC --------
  List<_DocRow> _docRowsForRequirement() {
    final rows = <_DocRow>[];
    void add(String label, String key, {bool pdf = false}) {
      rows.add(_DocRow(label: label, key: key, pdfAllowed: pdf));
    }

    if (_req.needsIdFront)   add('CNI – Recto *', 'nationalId_front');
    if (_req.needsIdBack)    add('CNI – Verso *', 'nationalId_back');
    if (_req.needsSelfie)    add('Selfie de vérification *', 'selfie');
    if (_req.needsLicense)   add('Permis de conduire *', 'driverLicense');
    if (_req.needsReg)       add('Carte grise *', 'vehicleRegistration');
    if (_req.needsIns)       add('Assurance véhicule *', 'vehicleInsurance');
    if (_req.needsPoA)       add('Justificatif de domicile (PDF/JPG, <3 mois) *', 'proofOfAddress', pdf: true);
    if (_req.needsIban)      add('IBAN / RIB *', 'iban', pdf: true);
    if (_req.needsBiz)       add('Identifiant professionnel (SIREN/SIRET/NIF…) *', 'businessStatus');
    if (_req.needsKbis)      add('Extrait registre (KBIS/RC) *', 'companyExtract', pdf: true);

    return rows;
  }

  Widget _buildKycChecklist() {
    final rows = _docRowsForRequirement();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Documents requis pour travailler légalement',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...rows.map((r) {
          final ok = _docsToUpload[r.key] != null;
          return ListTile(
            dense: true,
            leading: Icon(ok ? Icons.check_circle : Icons.upload_file),
            title: Text(r.label),
            subtitle: ok ? Text('Fichier importé', style: TextStyle(color: Colors.green[700])) : null,
            trailing: TextButton(
              onPressed: () => _pickAndStoreDoc(r.key, pdfAllowed: r.pdfAllowed),
              child: Text(ok ? 'Remplacer' : 'Importer'),
            ),
          );
        }),
      ],
    );
  }

  // ────────────── GPS helpers + RPC ─────────────────────────
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

  Future<Position?> _getPosition() async {
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Active la localisation et accepte la permission.')),
        );
      }
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateLocationOnce() async {
    final pos = await _getPosition();
    if (pos == null) throw Exception('Impossible d’obtenir la position.');
    await supabase.rpc('upsert_driver_location', params: {
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
    setState(() => _lastGpsAt = DateTime.now());
  }

  void _startLiveShare({Duration interval = const Duration(seconds: 20)}) {
    _gpsTimer?.cancel();
    _shareLive = true;
    _gpsTimer = Timer.periodic(interval, (_) async {
      try { await _updateLocationOnce(); } catch (_) {}
    });
  }

  void _stopLiveShare() {
    _shareLive = false;
    _gpsTimer?.cancel();
    _gpsTimer = null;
  }
  // ──────────────────────────────────────────────────────────

  // -------- Submit --------
  Future<void> _submit() async {
    if (_loading) return;

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrige les champs en rouge')),
      );
      return;
    }
    if (_country == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisis un pays')),
      );
      return;
    }
    if (_p1Bytes == null || _p2Bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute 2 photos du véhicule')),
      );
      return;
    }

    final missing = <String>[];
    for (final r in _docRowsForRequirement()) {
      if (_docsToUpload[r.key] == null) missing.add(r.label);
    }
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Documents manquants : ${missing.join(', ')}')),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu dois être connecté')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final already = await supabase
          .from('livreurs')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (already != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil déjà créé. Redirection…')),
        );
        Navigator.pushReplacementNamed(context, '/livreur_statut');
        return;
      }

      _p1Url = await _uploadVeh(_p1Bytes!, 'veh1');
      _p2Url = await _uploadVeh(_p2Bytes!, 'veh2');
      if (_p1Url == null || _p2Url == null) {
        throw 'Échec d’upload des photos';
      }

      final nomComplet =
          '${_prenomCtrl.text.trim()} ${_nomCtrl.text.trim()}'.trim();
      final prix = _prixCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_prixCtrl.text.trim());
      final phoneE164 = _buildE164();

      await supabase.from('livreurs').insert({
        'user_id'       : user.id,
        'nom'           : nomComplet,
        'prenom'        : _prenomCtrl.text.trim(),
        'phone'         : phoneE164,
        'pro'           : _pro,
        'type_livraison': _typeSelected,
        'zones'         : _zonesCtrl.text.trim(),
        'prix_suggere'  : prix,
        'negociable'    : _negociable,
        'pays'          : _country!.name,
        'country_iso'   : _country!.countryCode,
        'phone_code'    : _country!.phoneCode,
        'currency_code' : _currencyCode ?? _isoToCurrency[_country!.countryCode] ?? 'EUR',
        'photo1'        : _p1Url,
        'photo2'        : _p2Url,
        'required_docs' : {
          'nationalId_front'   : _req.needsIdFront,
          'nationalId_back'    : _req.needsIdBack,
          'selfie'             : _req.needsSelfie,
          'driverLicense'      : _req.needsLicense,
          'vehicleRegistration': _req.needsReg,
          'vehicleInsurance'   : _req.needsIns,
          'proofOfAddress'     : _req.needsPoA,
          'iban'               : _req.needsIban,
          'businessStatus'     : _req.needsBiz,
          'companyExtract'     : _req.needsKbis,
          'kyc_level'          : _req.level.name,
        },
        'docs'        : _docsToUpload,
        'doc_status'  : 'pending_review',
        'status'      : 'pending',
        'est_valide'  : false,
        'est_bloque'  : false,
      });

      await supabase.rpc('set_wallet_currency_from_country', params: {
        'p_user': user.id,
        'p_country_iso': _country!.countryCode,
      });

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/livreur_statut');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Supabase : ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;
    final maxW = 560.0;
    final priceLabel = _currencyCode == null
        ? 'Prix indicatif (optionnel)'
        : 'Prix indicatif (${_symbolFor(_currencyCode)} / ${_currencyCode}) (optionnel)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Livreur'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(pad),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Nom & prénom
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _prenomCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Prénom',
                                  prefixIcon: Icon(Icons.person_outline),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoire' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _nomCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nom',
                                  prefixIcon: Icon(Icons.person),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoire' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Pays
                        TextFormField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Pays',
                            prefixIcon: const Icon(Icons.public),
                            border: const OutlineInputBorder(),
                            hintText: _country?.name ?? 'Choisir un pays',
                            suffixIcon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          onTap: _pickCountry,
                          validator: (_) => _country == null ? 'Obligatoire' : null,
                        ),
                        const SizedBox(height: 12),

                        // Téléphone
                        TextFormField(
                          focusNode: _phoneFocus,
                          controller: _phoneCtrl,
                          enabled: _country != null,
                          decoration: InputDecoration(
                            labelText: 'Téléphone',
                            border: const OutlineInputBorder(),
                            prefixText: _country == null ? '' : '${_country!.flagEmoji} +$_dial ',
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: _validatePhone,
                        ),
                        const SizedBox(height: 12),

                        // Type
                        DropdownButtonFormField<String>(
                          value: _typeSelected,
                          items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _typeSelected = v!),
                          decoration: const InputDecoration(
                            labelText: 'Type de livraison',
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Zones
                        TextFormField(
                          controller: _zonesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Zones desservies (villes, quartiers…)',
                            prefixIcon: Icon(Icons.map_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoire' : null,
                        ),
                        const SizedBox(height: 12),

                        // Prix + options
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _prixCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: priceLabel,
                                  prefixIcon: const Icon(Icons.payments_outlined),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Négociable'),
                                    value: _negociable,
                                    onChanged: (v) => setState(() => _negociable = v),
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Compte PRO'),
                                    value: _pro,
                                    onChanged: (v) => setState(() => _pro = v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Checklist KYC
                        _buildKycChecklist(),
                        const SizedBox(height: 12),

                        // Photos véhicule
                        Row(
                          children: [
                            Expanded(
                              child: _PhotoPickerPreview(
                                bytes: _p1Bytes,
                                onPick: () => _pickImage(idx: 1),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _PhotoPickerPreview(
                                bytes: _p2Bytes,
                                onPick: () => _pickImage(idx: 2),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // ───────────── Localisation / GPS ─────────────
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Localisation',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.my_location),
                                        label: const Text('Détecter ma position'),
                                        onPressed: () async {
                                          try {
                                            await _updateLocationOnce();
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Position enregistrée.')),
                                            );
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Erreur GPS : $e')),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Temps réel'),
                                        value: _shareLive,
                                        onChanged: (v) {
                                          setState(() {
                                            if (v) {
                                              _startLiveShare(); // toutes les 20s
                                            } else {
                                              _stopLiveShare();
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (_lastGpsAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Dernier envoi : ${_lastGpsAt!.toLocal()}',
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Astuce : active “Temps réel” quand tu es en service. Tu peux le couper après.',
                                  style: TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ───────────────────────────────────────────────

                        const SizedBox(height: 6),

                        // Soumission
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Enregistrer et envoyer pour validation',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _DocRow {
  final String label;
  final String key;
  final bool pdfAllowed;
  _DocRow({required this.label, required this.key, this.pdfAllowed = false});
}

class _PhotoPickerPreview extends StatelessWidget {
  final Uint8List? bytes;
  final VoidCallback onPick;
  const _PhotoPickerPreview({required this.bytes, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            image: bytes != null ? DecorationImage(image: MemoryImage(bytes!), fit: BoxFit.cover) : null,
          ),
          child: bytes == null
              ? const Center(child: Icon(Icons.add_a_photo, size: 36, color: Colors.black54))
              : null,
        ),
      ),
    );
  }
}
