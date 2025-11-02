
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LivreurProfileEditPage extends StatefulWidget {
  const LivreurProfileEditPage({super.key, required this.livreurId});
  final String livreurId;

  @override
  State<LivreurProfileEditPage> createState() => _LivreurProfileEditPageState();
}

class _LivreurProfileEditPageState extends State<LivreurProfileEditPage> {
  final supa = Supabase.instance.client;
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  Uint8List? _photoBytes;
  String? _photoMime;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await supa.from('livreurs')
        .select('*, ...')
        .eq('id', widget.livreurId)
        .single();

      final row = Map<String, dynamic>.from(res as Map);

      _nom.text = (row['nom'] ?? '').toString();
      _prenom.text = (row['prenom'] ?? '').toString();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (x == null) return;
    final b = await x.readAsBytes();
    final m = lookupMimeType(x.name, headerBytes: b) ?? 'image/jpeg';
    setState(() { _photoBytes = b; _photoMime = m; });
  }

  Future<String?> _upload(String id) async {
    if (_photoBytes == null || _photoBytes!.isEmpty) return null;
    final path = 'livreurs/$id.jpg';
    await supa.storage.from('profiles').uploadBinary(
      path, _photoBytes!,
      fileOptions: FileOptions(contentType: _photoMime, upsert: true),
    );
    return supa.storage.from('profiles').getPublicUrl(path);
  }

  Future<void> _save() async {
    if (_nom.text.trim().isEmpty || _prenom.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nom et prénom requis.')));
      return;
    }
    try {
      String? photoUrl = await _upload(widget.livreurId);
      final update = {
        'nom': _nom.text.trim(),
        'prenom': _prenom.text.trim(),
      };
      if (photoUrl != null) {
        // tente photo_url puis photo1
        update['photo_url'] = photoUrl;
        try {
          await supa.from('livreurs').update(update).eq('id', widget.livreurId);
        } catch (_) {
          update.remove('photo_url');
          update['photo1'] = photoUrl;
          await supa.from('livreurs').update(update).eq('id', widget.livreurId);
        }
      } else {
        await supa.from('livreurs').update(update).eq('id', widget.livreurId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour.')));
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Supabase: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(controller: _prenom, decoration: const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: _nom, decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  Row(children: [
                    ElevatedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.photo), label: const Text('Choisir une photo')),
                    const SizedBox(width: 10),
                    if (_photoBytes != null) const Icon(Icons.check_circle, color: Colors.green),
                  ]),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: _save, child: const Text('Enregistrer')),
                  ),
                ],
              ),
            ),
    );
  }
}
