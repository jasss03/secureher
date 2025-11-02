import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SafeZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters; // default 150m
  SafeZone({required this.id, required this.name, required this.lat, required this.lng, this.radiusMeters = 150});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radiusMeters,
      };

  static SafeZone fromJson(Map<String, dynamic> j) => SafeZone(
        id: j['id'],
        name: j['name'] ?? 'Zone',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusMeters: (j['radius'] as num?)?.toDouble() ?? 150,
      );
}

class SafeZoneService {
  static const _key = 'safe_zones_v1';

  Future<List<SafeZone>> getZones() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(SafeZone.fromJson).toList();
  }

  Future<void> saveZones(List<SafeZone> zones) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(zones.map((z) => z.toJson()).toList()));
  }

  Future<void> addZone(SafeZone z) async {
    final list = await getZones();
    list.add(z);
    await saveZones(list);
  }

  Future<void> removeZone(String id) async {
    final list = await getZones();
    list.removeWhere((z) => z.id == id);
    await saveZones(list);
  }

  // Compute if a position is inside any zone
  bool isInsideAny(Position p, List<SafeZone> zones) {
    for (final z in zones) {
      final d = Geolocator.distanceBetween(p.latitude, p.longitude, z.lat, z.lng);
      if (d <= z.radiusMeters) return true;
    }
    return false;
  }
}