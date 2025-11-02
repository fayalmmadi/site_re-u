import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MesVehiculesPage extends StatefulWidget {
  const MesVehiculesPage({super.key, required this.livreurId});
  final String livreurId;

  @override
  State<MesVehiculesPage> createState() => _MesVehiculesPageState();
}

class _MesVehiculesPageState extends State<MesVehiculesPage> {
  final supa = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _load() async {
    final List data = await supa
        .from('livreur_vehicules')
        .select()
        .eq('livreur_id', widget.livreurId)
        .order('created_at', ascending: false);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> _addOrEdit({Map<String, dynamic>? initial}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _VehiculeFormSheet(
        livreurId: widget.livreurId,
        initial: initial,
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le véhicule ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await supa.from('livreur_vehicules').delete().eq('id', id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Véhicule supprimé')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes véhicules'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _addOrEdit()),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (_, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_car_outlined, size: 56, color: Colors.black38),
                    const SizedBox(height: 8),
                    const Text('Aucun véhicule.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _addOrEdit(),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un véhicule'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final v = rows[i];
              final title = (v['titre'] ?? 'Véhicule').toString();
              final type = (v['type'] ?? '—').toString();
              final plate = (v['plate'] ?? '—').toString();
              final zones = (v['zones'] ?? '—').toString();
              final p1 = (v['photo1'] ?? '').toString();
              final p2 = (v['photo2'] ?? '').toString();

              Widget thumb(String? url) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: (url == null || url.isEmpty)
                          ? Container(color: const Color(0xFFEDEDED), child: const Icon(Icons.image))
                          : Image.network(url, fit: BoxFit.cover),
                    ),
                  );

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Column(children: [
                          thumb(p1),
                          const SizedBox(height: 6),
                          thumb(p2),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('Type : $type'),
                          Text('Immatriculation : $plate'),
                          Text('Zones : $zones', maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _addOrEdit(initial: v),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Modifier'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _delete(v['id'] as String),
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                label: const Text('Supprimer', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/* -------------------- Sheet ajout / édition -------------------- */

class _VehiculeFormSheet extends StatefulWidget {
  const _VehiculeFormSheet({required this.livreurId, this.initial});
  final String livreurId;
  final Map<String, dynamic>? initial;

  @override
  State<_VehiculeFormSheet> createState() => _VehiculeFormSheetState();
}

class _VehiculeFormSheetState extends State<_VehiculeFormSheet> {
  final supa = Supabase.instance.client;

  final _titre = TextEditingController();
  final _type = TextEditingController();
  final _plate = TextEditingController();
  final _zones = TextEditingController();

  Uint8List? _p1;
  Uint8List? _p2;
  String? _p1Mime;
  String? _p2Mime;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    if (v != null) {
      _titre.text = (v['titre'] ?? '').toString();
      _type.text = (v['type'] ?? '').toString();
      _plate.text = (v['plate'] ?? '').toString();
      _zones.text = (v['zones'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _titre.dispose();
    _type.dispose();
    _plate.dispose();
    _zones.dispose();
    super.dispose();
  }

  Future<void> _pick(int which) async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (p == null) return;
    final bytes = await p.readAsBytes();
    final mime = lookupMimeType(p.name, headerBytes: bytes) ?? 'image/jpeg';
    setState(() {
      if (which == 1) {
        _p1 = bytes;
        _p1Mime = mime;
      } else {
        _p2 = bytes;
        _p2Mime = mime;
      }
    });
  }

  Future<String> _uploadBytes(String vehId, Uint8List bytes, String? mime, int index) async {
    final contentType = mime ?? 'image/jpeg';
    final path = 'vehicules/$vehId-$index.jpg';
    await supa.storage.from('vehicles').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    return supa.storage.from('vehicles').getPublicUrl(path);
    }

  Future<void> _save() async {
    final isEdit = widget.initial != null;
    final id = (widget.initial?['id'] as String?);

    final payload = <String, dynamic>{
      'livreur_id': widget.livreurId,
      'titre': _titre.text.trim(),
      'type': _type.text.trim(),
      'plate': _plate.text.trim(),
      'zones': _zones.text.trim(),
    };

    try {
      Map<String, dynamic> row;
      if (isEdit) {
        row = await supa.from('livreur_vehicules').update(payload).eq('id', id!).select().single();
      } else {
        row = await supa.from('livreur_vehicules').insert(payload).select().single();
      }

      final vehId = row['id'] as String;

      String? url1 = row['photo1'] as String?;
      String? url2 = row['photo2'] as String?;

      if (_p1 != null && _p1!.isNotEmpty) {
        url1 = await _uploadBytes(vehId, _p1!, _p1Mime, 1);
      }
      if (_p2 != null && _p2!.isNotEmpty) {
        url2 = await _uploadBytes(vehId, _p2!, _p2Mime, 2);
      }

      if (_p1 != null || _p2 != null) {
        row = await supa
            .from('livreur_vehicules')
            .update({'photo1': url1, 'photo2': url2})
            .eq('id', vehId)
            .select()
            .single();
      }

      if (!mounted) return;
      Navigator.pop(context, true); // ✅ signale au dashboard de recharger
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? 'Véhicule mis à jour' : 'Véhicule ajouté')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur Supabase: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
    );

    final isEdit = widget.initial != null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, width: 40, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            Text(isEdit ? 'Modifier le véhicule' : 'Ajouter un véhicule',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),

            TextField(controller: _titre, decoration: const InputDecoration(labelText: 'Titre (ex: Clio blanche)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _type, decoration: const InputDecoration(labelText: 'Type (moto, voiture, camion...)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Immatriculation', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _zones, maxLines: 2, decoration: const InputDecoration(labelText: 'Zones', border: OutlineInputBorder())),
            const SizedBox(height: 12),

            Row(
              children: [
                ElevatedButton.icon(onPressed: () => _pick(1), icon: const Icon(Icons.photo), label: const Text('Photo 1')),
                const SizedBox(width: 8),
                if (_p1 != null) const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 16),
                ElevatedButton.icon(onPressed: () => _pick(2), icon: const Icon(Icons.photo_library), label: const Text('Photo 2')),
                const SizedBox(width: 8),
                if (_p2 != null) const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
