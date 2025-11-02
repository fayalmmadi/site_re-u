import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';

class ClientRepository {
  static const _kClientId = 'client_id_cache';
  final supabase = Supabase.instance.client;

  Future<Map<String,dynamic>?> getFromCache() async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getString(_kClientId);
    if (id == null) return null;
    final row = await supabase.from('clients').select().eq('id', id).maybeSingle();
    return row == null ? null : Map<String,dynamic>.from(row);
  }

  Future<void> saveIdToCache(String id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kClientId, id);
  }

  Future<Map<String,dynamic>> reload(String id) async {
    final row = await supabase.from('clients').select().eq('id', id).single();
    return Map<String,dynamic>.from(row);
  }

  Future<String> uploadPhoto(String clientId, Uint8List bytes, {String? mimeType}) async {
    final contentType = mimeType ?? lookupMimeType('', headerBytes: bytes) ?? 'image/jpeg';
    final path = 'clients/$clientId.jpg';
    await supabase.storage.from('profiles').uploadBinary(
      path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    return supabase.storage.from('profiles').getPublicUrl(path);
  }
}
