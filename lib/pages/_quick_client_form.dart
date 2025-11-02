import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';

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
  final _phone = TextEditingController(); // <-- ne contient QUE les chiffres locaux

  Country _country = CountryParser.parseCountryCode('KM'); // Comores par défaut

  String _localPart(String t) => t.trim().replaceFirst(RegExp(r'^\+\d+\s*'), '');

  @override
  void initState() {
    super.initState();

    // Si on passe un numéro complet (+code …), on ne garde que la partie locale
    if (widget.prefillPhone != null && widget.prefillPhone!.isNotEmpty) {
      _phone.text = _localPart(widget.prefillPhone!);
    }

    // Si l’utilisateur colle un numéro avec +code, on l’assainit instantanément.
    _phone.addListener(() {
      final t = _phone.text;
      final local = _localPart(t);
      if (t != local) {
        _phone.value = TextEditingValue(
          text: local,
          selection: TextSelection.collapsed(offset: local.length),
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

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (c) => setState(() => _country = c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.only(
      left: 16, right: 16, top: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, width: 40,
              decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('Créer / mettre à jour votre profil',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),

            InkWell(
              onTap: _pickCountry,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Pays', border: OutlineInputBorder()),
                child: Row(
                  children: [
                    Text(_country.flagEmoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${_country.name} (+${_country.phoneCode})', overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.keyboard_arrow_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(child: TextField(
                  controller: _prenom,
                  decoration: const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder()),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _nom,
                  decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
                )),
              ],
            ),
            const SizedBox(height: 10),

            // IMPORTANT: seul prefixText affiche l’indicatif ; le controller ne contient PAS le +code
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Téléphone',
                prefixText: '+${_country.phoneCode} ',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (facultatif)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_nom.text.trim().isEmpty ||
                      _prenom.text.trim().isEmpty ||
                      _phone.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nom, prénom et téléphone sont requis.')),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _QuickClientResult(
                      nom: _nom.text.trim(),
                      prenom: _prenom.text.trim(),
                      // On recompose le numéro complet SEULEMENT à la sortie
                      phone: '+${_country.phoneCode} ${_phone.text.trim()}',
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
