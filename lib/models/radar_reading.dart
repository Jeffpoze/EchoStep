import '../config.dart';
import 'relic.dart';

enum GamePhase { locating, hunting, excavating, allCollected }

/// Snapshot of the spatial relationship between the player and the nearest relic.
class RadarReading {
  const RadarReading({
    required this.target,
    required this.distance,
    required this.bearing,
    required this.angleDelta,
  });

  final Relic target;

  /// Meters to the target.
  final double distance;

  /// Absolute bearing from player to target, 0..360.
  final double bearing;

  /// Signed angle (-180..180) between where the player faces and the target.
  final double angleDelta;

  bool get isAligned => angleDelta.abs() <= kAlignedDegrees;

  /// 0 when far (>= spawn max), 1 at the excavation radius.
  double get closeness {
    final t = (kSpawnMaxMeters - distance) / (kSpawnMaxMeters - kExcavationRadius);
    return t.clamp(0.0, 1.0);
  }

  /// 1 when facing within ±15°, falling to 0 when facing directly away.
  double get brightness {
    final a = angleDelta.abs();
    if (a <= kAlignedDegrees) return 1.0;
    return (1.0 - (a - kAlignedDegrees) / (180 - kAlignedDegrees)).clamp(0.0, 1.0);
  }
}
