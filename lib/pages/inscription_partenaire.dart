// lib/pages/inscription_partenaire_page.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:country_picker/country_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBrand = Color(0xFF084C28);

/// ───────────────────────────────────────────────────────────
/// 1) KYC par pays
/// ───────────────────────────────────────────────────────────
enum KycLevel { minimum, enhanced, financial }

enum KycDocType {
  nationalId,
  selfie,
  proofOfAddress,
  iban,
  businessStatus,
  companyExtract,
  contractConsent,
  phoneOtp,
  emailOtp,
}

@immutable
class KycRequirement {
  final KycLevel level;
  final Set<KycDocType> requiredDocs;
  final List<String> hints;

  const KycRequirement({
    required this.level,
    required this.requiredDocs,
    this.hints = const [],
  });

  bool get needsId       => requiredDocs.contains(KycDocType.nationalId);
  bool get needsSelfie   => requiredDocs.contains(KycDocType.selfie);
  bool get needsProofAdr => requiredDocs.contains(KycDocType.proofOfAddress);
  bool get needsIban     => requiredDocs.contains(KycDocType.iban);
  bool get needsBiz      => requiredDocs.contains(KycDocType.businessStatus);
  bool get needsKbis     => requiredDocs.contains(KycDocType.companyExtract);
}

const _defaultReq = KycRequirement(
  level: KycLevel.minimum,
  requiredDocs: {
    KycDocType.nationalId,
    KycDocType.contractConsent,
    KycDocType.emailOtp,
    KycDocType.phoneOtp,
  },
  hints: ["KYC minimum : CNI (recto/verso), OTP email/SMS, consentement."],
);

final Map<String, KycRequirement> kycByCountry = {
  // UE/EEE
  'FR': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.companyExtract,
      KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: [
      "France : activité rémunérée ⇒ SIREN/SIRET obligatoire.",
      "KBIS < 3 mois si société. IBAN requis pour paiements.",
      "Respect des obligations sociales/fiscales (URSSAF, TVA le cas échéant).",
    ],
  ),
  'DE': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["DE : Identifiant pro si rémunération ; IBAN requis."],
  ),
  'ES': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["ES : NIE/CIF selon statut ; IBAN requis."],
  ),
  'IT': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["IT : Partita IVA si assujetti TVA."],
  ),
  'GB': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["UK : Companies House/UTR selon statut."],
  ),

  // Autres marchés financiers
  'US': KycRequirement(
    level: KycLevel.financial,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["US : EIN/SSN/ITIN selon statut."],
  ),
  'CA': KycRequirement(
    level: KycLevel.financial,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["CA : FINTRAC ; NE requis si société."],
  ),
  'CH': KycRequirement(
    level: KycLevel.financial,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.selfie, KycDocType.proofOfAddress,
      KycDocType.iban, KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["CH : LBA stricte ; justificatif domicile requis."],
  ),

  // Maghreb / Afrique (ex.)
  'MA': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.proofOfAddress, KycDocType.iban,
      KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["MA : IF/RC selon statut ; RIB requis pour paiements."],
  ),
  'TN': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.proofOfAddress, KycDocType.iban,
      KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["TN : Matricule fiscal si pro."],
  ),
  'DZ': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.proofOfAddress, KycDocType.iban,
      KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["DZ : NIF/RC si société."],
  ),
  'KE': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.proofOfAddress, KycDocType.iban,
      KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["KE : KRA PIN ; mobile money exige KYC."],
  ),
  'ZA': KycRequirement(
    level: KycLevel.enhanced,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.proofOfAddress, KycDocType.iban,
      KycDocType.businessStatus, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["ZA : FICA bancaire stricte."],
  ),

  // Comores / Madagascar / Sénégal
  'KM': KycRequirement(
    level: KycLevel.minimum,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.contractConsent, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["KM : KYC minimum ; ajoute IBAN/statut pro si paiements."],
  ),
  'MG': KycRequirement(
    level: KycLevel.minimum,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.contractConsent, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["MG : mobile money demande souvent CNI + selfie."],
  ),
  'SN': KycRequirement(
    level: KycLevel.minimum,
    requiredDocs: {
      KycDocType.nationalId, KycDocType.contractConsent, KycDocType.emailOtp, KycDocType.phoneOtp,
    },
    hints: ["SN : NINEA/RC si société ; RIB si paiements."],
  ),
};

KycRequirement requirementForCountry(String? iso2) {
  if (iso2 == null || iso2.isEmpty) return _defaultReq;
  return kycByCountry[iso2.toUpperCase()] ?? _defaultReq;
}

/// ───────────────────────────────────────────────────────────
/// 2) Page d’inscription partenaire
/// ───────────────────────────────────────────────────────────
class InscriptionPartenairePage extends StatefulWidget {
  const InscriptionPartenairePage({Key? key}) : super(key: key);

  @override
  State<InscriptionPartenairePage> createState() => _InscriptionPartenairePageState();
}

class _InscriptionPartenairePageState extends State<InscriptionPartenairePage> {
  final supa = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Identité & contact
  final prenomCtrl = TextEditingController();
  final nomCtrl = TextEditingController();
  final telephoneCtrl = TextEditingController();
  final paysNaissanceCtrl = TextEditingController();
  final departementCtrl = TextEditingController();

  // Champs KYC conditionnels
  final ibanCtrl = TextEditingController();
  final businessIdCtrl = TextEditingController();

  // Pays sélectionné
  String? _countryIso;   // ex: KM
  String? _countryName;  // ex: Comoros (pour l’affichage)
  Map<String, dynamic>? _countryDefaults; // currency_code/lang/timezone/decimals
  KycRequirement _req = _defaultReq;

  // Uploads
  Uint8List? _avatarBytes;
  Uint8List? _idFrontBytes;
  Uint8List? _idBackBytes;
  Uint8List? _proofAddressBytes;
  Uint8List? _kbisBytes;

  // Attestation / état
  bool _attestationOk = false;
  bool _submitting = false;

  @override
  void dispose() {
    prenomCtrl.dispose();
    nomCtrl.dispose();
    telephoneCtrl.dispose();
    paysNaissanceCtrl.dispose();
    departementCtrl.dispose();
    ibanCtrl.dispose();
    businessIdCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {bool required = true, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      suffixIcon: suffixIcon,
    );
  }

  String? _requiredText(String? v) => (v == null || v.trim().isEmpty) ? 'Obligatoire' : null;

  // Pickers
  Future<Uint8List?> _pickImage() async {
    try {
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.image, withData: true, allowMultiple: false);
        return res?.files.single.bytes;
      } else {
        final picker = ImagePicker();
        final f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        return f == null ? null : await f.readAsBytes();
      }
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _pickDocPdfOrImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      return res?.files.single.bytes;
    } catch (_) {
      return null;
    }
  }

  // Upload Storage
  Future<String?> _upload(String bucket, Uint8List bytes, String filename,
      {String contentType = 'image/jpeg'}) async {
    final uid = supa.auth.currentUser!.id;
    final path = 'partners/$uid/$filename';
    await supa.storage.from(bucket).uploadBinary(
      path, bytes, fileOptions: FileOptions(upsert: true, contentType: contentType));
    return supa.storage.from(bucket).getPublicUrl(path);
  }

  /// Sélection du pays → charge les defaults depuis `country_defaults`
  void _selectCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (Country c) async {
        try {
          final row = await supa
              .from('country_defaults')
              .select('country, currency_code, language_code, timezone, currency_decimals')
              .eq('country', c.countryCode) // colonne = country (ISO-2)
              .maybeSingle();

          setState(() {
            _countryIso = c.countryCode; // KM
            _countryName = c.name;       // Comoros (affichage)
            _req = requirementForCountry(_countryIso);
            _countryDefaults = row ?? {};
          });

          final cur = _countryDefaults?['currency_code'] ?? 'EUR';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pays : ${c.name} — Devise : $cur'), backgroundColor: kBrand),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur chargement pays : $e')),
          );
        }
      },
    );
  }

  // Soumission formulaire
  Future<void> _submit() async {
    if (_countryIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionne le pays d’opération.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Gardiens KYC
    if (_req.needsId && (_idFrontBytes == null || _idBackBytes == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce pays exige CNI recto ET verso.')),
      );
      return;
    }
    if (_req.needsSelfie && _avatarBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce pays exige une photo selfie.')),
      );
      return;
    }
    if (_req.needsProofAdr && _proofAddressBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Justificatif de domicile requis.')),
      );
      return;
    }
    if (_req.needsIban && ibanCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IBAN/RIB obligatoire pour ce pays.')),
      );
      return;
    }
    if (_req.needsBiz && businessIdCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identifiant pro requis (SIREN/SIRET/NIF…).')),
      );
      return;
    }
    if (!_attestationOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coche l’attestation et accepte les CGU.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final user = supa.auth.currentUser!;
      String? avatarUrl, idFrontUrl, idBackUrl, proofUrl, kbisUrl;

      if (_avatarBytes != null)  avatarUrl  = await _upload('avatars', _avatarBytes!, 'selfie.jpg');
      if (_idFrontBytes != null) idFrontUrl = await _upload('ids', _idFrontBytes!, 'id_front.jpg');
      if (_idBackBytes != null)  idBackUrl  = await _upload('ids', _idBackBytes!, 'id_back.jpg');
      if (_proofAddressBytes != null) {
        proofUrl = await _upload('docs', _proofAddressBytes!, 'proof_address',
            contentType: 'application/octet-stream');
      }
      if (_req.needsKbis && _kbisBytes != null) {
        kbisUrl = await _upload('docs', _kbisBytes!, 'kbis_or_register',
            contentType: 'application/octet-stream');
      }

      // Récup defaults pays (sécurités)
      final currencyCode   = _countryDefaults?['currency_code'];
      final languageCode   = _countryDefaults?['language_code'];
      final timezone       = _countryDefaults?['timezone'];
      final currencyDec    = _countryDefaults?['currency_decimals'];

      // Upsert partenaire (user_id = auth.uid())
      final payload = <String, dynamic>{
        'user_id' : user.id,
        'email'   : user.email,

        // Identité
        'prenom'  : prenomCtrl.text.trim(),
        'nom'     : nomCtrl.text.trim(),
        'telephone': telephoneCtrl.text.trim(),
        'pays_naissance'      : paysNaissanceCtrl.text.trim(),
        'departement_naissance': departementCtrl.text.trim(),

        // Pays & KYC
        'country_iso' : _countryIso,        // ex: KM
        // 'country_name': _countryName,     // <- ajoute si ta table a cette colonne
        'kyc_level'   : _req.level.name,

        // Defaults pays (si colonnes présentes)
        if (currencyCode != null)   'currency_code'    : currencyCode,   // ex: KMF
        if (languageCode != null)   'language_code'    : languageCode,   // ex: fr
        if (timezone != null)       'timezone'         : timezone,       // ex: Indian/Comoro
        if (currencyDec != null)    'currency_decimals': currencyDec,    // ex: 0

        // URLs documents
        if (avatarUrl  != null) 'avatar_url'        : avatarUrl,
        if (idFrontUrl != null) 'id_card_front_url' : idFrontUrl,
        if (idBackUrl  != null) 'id_card_back_url'  : idBackUrl,
        if (proofUrl   != null) 'proof_address_url' : proofUrl,
        if (kbisUrl    != null) 'kbis_url'          : kbisUrl,

        // Champs conditionnels FR/UE…
        if (_req.needsIban) 'iban'        : ibanCtrl.text.trim(),
        if (_req.needsBiz)  'business_id' : businessIdCtrl.text.trim(),

        // Statut
        'est_valide'   : false,
        'est_bloque'   : false,
        'status'       : 'pending',
        'requested_at' : DateTime.now().toIso8601String(),
        'reviewed_at'  : null,
        'reviewer_id'  : null,

        // Attestation / CGU
        'attestation_ok'   : true,
        'attestation_at'   : DateTime.now().toIso8601String(),
        'cgu_accepted'     : true,
        'cgu_accepted_at'  : DateTime.now().toIso8601String(),
        'cgu_version'      : 'v1.0',
      };

      await supa.from('partenaires').upsert(payload, onConflict: 'user_id');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/partenaire_statut');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = supa.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kBrand,
        title: const Text('Inscription Partenaire', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // Header profil
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: kBrand.withOpacity(.1),
                            backgroundImage: _avatarBytes != null ? MemoryImage(_avatarBytes!) : null,
                            child: _avatarBytes == null
                                ? const Icon(Icons.person, color: kBrand)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('+ Téléphone à remplir ci-dessous',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final bytes = await _pickImage();
                              if (bytes != null) setState(() => _avatarBytes = bytes);
                            },
                            icon: const Icon(Icons.image),
                            label: Text(_req.needsSelfie ? 'Photo selfie *' : 'Photo selfie'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Pays d’opération
                      TextFormField(
                        readOnly: true,
                        controller: TextEditingController(text: _countryName ?? ''),
                        decoration: _dec(
                          'Pays d’opération',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.public),
                            onPressed: _selectCountry,
                          ),
                        ),
                        validator: (_) => (_countryIso == null) ? 'Obligatoire' : null,
                      ),

                      if (_countryIso != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _req.level == KycLevel.minimum
                                ? Colors.amber.shade100
                                : _req.level == KycLevel.enhanced
                                    ? Colors.blue.shade100
                                    : Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _req.level == KycLevel.minimum
                                ? 'Minimum KYC'
                                : _req.level == KycLevel.enhanced
                                    ? 'KYC renforcé'
                                    : 'KYC financier',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        // Hints + récap devise/decimals
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            () {
                              final cur = _countryDefaults?['currency_code'] ?? 'EUR';
                              final dec = _countryDefaults?['currency_decimals'] ?? 2;
                              final extraHints = _req.hints.join(' ');
                              return '${_countryName ?? ''} : KYC ${_req.level.name}. '
                                     'Devise $cur, $dec décimale(s). $extraHints';
                            }(),
                            style: TextStyle(color: Colors.grey[700], fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Identité
                      TextFormField(controller: prenomCtrl, decoration: _dec('Prénom'), validator: _requiredText),
                      const SizedBox(height: 12),
                      TextFormField(controller: nomCtrl, decoration: _dec('Nom'), validator: _requiredText),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: telephoneCtrl,
                        decoration: _dec('Téléphone'),
                        keyboardType: TextInputType.phone,
                        validator: _requiredText,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: paysNaissanceCtrl, decoration: _dec('Pays de naissance'), validator: _requiredText),
                      const SizedBox(height: 12),
                      TextFormField(controller: departementCtrl, decoration: _dec('Département de naissance'), validator: _requiredText),
                      const SizedBox(height: 16),

                      // CNI recto/verso (si requis)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Carte d’identité (recto)${_req.needsId ? ' *' : ''}'),
                        subtitle: Text(_idFrontBytes == null ? 'Aucune image choisie' : '1 fichier sélectionné',
                          style: TextStyle(color: Colors.grey[700])),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: kBrand),
                          onPressed: () async {
                            final b = await _pickImage();
                            if (b != null) setState(() => _idFrontBytes = b);
                          },
                          icon: const Icon(Icons.credit_card, color: Colors.white),
                          label: const Text('Recto', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Carte d’identité (verso)${_req.needsId ? ' *' : ''}'),
                        subtitle: Text(_idBackBytes == null ? 'Aucune image choisie' : '1 fichier sélectionné',
                          style: TextStyle(color: Colors.grey[700])),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: kBrand),
                          onPressed: () async {
                            final b = await _pickImage();
                            if (b != null) setState(() => _idBackBytes = b);
                          },
                          icon: const Icon(Icons.credit_card_outlined, color: Colors.white),
                          label: const Text('Verso', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Justificatif de domicile (si requis)
                      if (_req.needsProofAdr) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Justificatif de domicile (PDF/JPG, < 3 mois) *'),
                          subtitle: Text(_proofAddressBytes == null ? 'Aucun fichier choisi' : '1 fichier sélectionné',
                            style: TextStyle(color: Colors.grey[700])),
                          trailing: OutlinedButton.icon(
                            onPressed: () async {
                              final b = await _pickDocPdfOrImage();
                              if (b != null) setState(() => _proofAddressBytes = b);
                            },
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Téléverser'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Identifiant pro & KBIS (si requis)
                      if (_req.needsBiz) ...[
                        TextFormField(
                          controller: businessIdCtrl,
                          decoration: _dec('Identifiant professionnel (SIREN/SIRET, NIF, RCCM…)'),
                          validator: _requiredText,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_req.needsKbis) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Extrait registre (KBIS/RC, PDF/JPG) *'),
                          subtitle: Text(_kbisBytes == null ? 'Aucun fichier choisi' : '1 fichier sélectionné',
                            style: TextStyle(color: Colors.grey[700])),
                          trailing: OutlinedButton.icon(
                            onPressed: () async {
                              final b = await _pickDocPdfOrImage();
                              if (b != null) setState(() => _kbisBytes = b);
                            },
                            icon: const Icon(Icons.upload),
                            label: const Text('Téléverser'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // IBAN (si requis)
                      if (_req.needsIban) ...[
                        TextFormField(controller: ibanCtrl, decoration: _dec('IBAN / RIB'), validator: _requiredText),
                        const SizedBox(height: 16),
                      ],

                      // Attestation
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _attestationOk,
                        onChanged: (v) => setState(() => _attestationOk = v ?? false),
                        title: const Text("J’atteste sur l’honneur *"),
                        subtitle: const Text(
                          "Je déclare que les informations sont exactes, que j’exerce une activité légale "
                          "et j’accepte les CGU. Je respecterai les obligations locales (travail & fiscalité).",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Envoyer
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBrand,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(height: 22, width: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Envoyer ma demande', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
