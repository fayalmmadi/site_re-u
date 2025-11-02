import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class LivreursService {
  final _sb = Supabase.instance.client;
  final _stream = StreamController<List<Map<String,dynamic>>>.broadcast();
  Timer? _timer;

  Stream<List<Map<String,dynamic>>> get nearbyStream => _stream.stream;

  Future<void> start(double lat, double lng, {double radiusKm = 10, Duration every = const Duration(seconds: 10)}) async {
    Future<void> load() async {
      final res = await _sb.rpc('get_nearby_livreurs', params: {
        'p_lat': lat, 'p_lng': lng, 'p_radius_km': radiusKm,
      });
      _stream.add(List<Map<String,dynamic>>.from(res as List));
    }
    await load();
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => load());
  }

  void dispose() { _timer?.cancel(); _stream.close(); }
}
