import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../utils/geo_math.dart';

/// Magnetometer heading, overridable by the desk simulator slider.
class HeadingService {
  HeadingService({required this.onHeading});

  final ValueChanged<double> onHeading;

  StreamSubscription<CompassEvent>? _sub;
  bool simulated = false;
  bool hasSensor = false;
  double _real = 0;
  double _sim = 0;

  double get heading => simulated ? _sim : _real;

  void start() {
    final stream = FlutterCompass.events;
    if (stream == null) return;
    _sub = stream.listen(
      (e) {
        final h = e.heading;
        if (h == null) return;
        hasSensor = true;
        final next = GeoMath.normalize360(h);
        // Ignore sub-degree jitter to avoid spamming rebuilds.
        if ((GeoMath.signedDelta(_real, next)).abs() < 1) return;
        _real = next;
        if (!simulated) onHeading(_real);
      },
      onError: (Object e) => debugPrint('Compass unavailable: $e'),
    );
  }

  void setSimulated(bool on) {
    simulated = on;
    onHeading(heading);
  }

  void setSimulatedHeading(double deg) {
    _sim = GeoMath.normalize360(deg);
    if (simulated) onHeading(_sim);
  }

  void dispose() => _sub?.cancel();
}
