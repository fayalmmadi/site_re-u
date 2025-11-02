import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlacesService {
  PlacesService(this.apiKey);
  final String apiKey;

  Future<List<Map<String,dynamic>>> autocomplete(String input, String sessionToken) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': input, 'types':'geocode', 'language':'fr', 'sessiontoken': sessionToken, 'key': apiKey,
    });
    final res = await http.get(uri);
    final data = json.decode(res.body);
    if (data['status'] != 'OK') return [];
    return List<Map<String,dynamic>>.from(data['predictions']);
  }

  Future<(LatLng,String)?> details(String placeId, String sessionToken) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId, 'fields':'geometry/location,formatted_address', 'language':'fr', 'key': apiKey, 'sessiontoken': sessionToken,
    });
    final res = await http.get(uri);
    final data = json.decode(res.body);
    if (data['status'] != 'OK') return null;
    final loc = data['result']['geometry']['location'];
    final addr = data['result']['formatted_address'] ?? '';
    return (LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()), addr);
  }
}
