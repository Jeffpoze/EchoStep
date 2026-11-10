import 'dart:math' as math;

/// Simple lat/lng value type, independent of any map SDK.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  String toString() => '(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}

class GeoMath {
  static const double earthRadius = 6371000.0;

  static double _rad(double d) => d * math.pi / 180.0;
  static double _deg(double r) => r * 180.0 / math.pi;

  /// Haversine distance in meters.
  static double distance(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.lat - a.lat);
    final dLng = _rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(h.toDouble()));
  }

  /// Initial bearing from [a] to [b], normalized to 0..360 (0 = north).
  static double bearing(GeoPoint a, GeoPoint b) {
    final lat1 = _rad(a.lat);
    final lat2 = _rad(b.lat);
    final dLng = _rad(b.lng - a.lng);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return normalize360(_deg(math.atan2(y, x)));
  }

  /// Point reached travelling [meters] from [origin] along [bearingDeg].
  static GeoPoint offset(GeoPoint origin, double bearingDeg, double meters) {
    final d = meters / earthRadius;
    final brng = _rad(bearingDeg);
    final lat1 = _rad(origin.lat);
    final lng1 = _rad(origin.lng);
    final lat2 = math.asin(math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(brng));
    final lng2 = lng1 +
        math.atan2(math.sin(brng) * math.sin(d) * math.cos(lat1), math.cos(d) - math.sin(lat1) * math.sin(lat2));
    return GeoPoint(_deg(lat2), _deg(lng2));
  }

  /// Move by north/east meter deltas (used by the desk simulator D-pad).
  static GeoPoint moveNE(GeoPoint origin, double northMeters, double eastMeters) {
    final meters = math.sqrt(northMeters * northMeters + eastMeters * eastMeters);
    if (meters == 0) return origin;
    final brng = _deg(math.atan2(eastMeters, northMeters));
    return offset(origin, brng, meters);
  }

  static double normalize360(double deg) {
    final r = deg % 360.0;
    return r < 0 ? r + 360.0 : r;
  }

  /// Signed shortest angle from [from] to [to], in -180..180.
  static double signedDelta(double from, double to) {
    var d = (to - from) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }
}
