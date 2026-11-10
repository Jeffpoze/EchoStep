import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/geo_math.dart';

/// Real GPS tracking via geolocator, with a virtual position for the desk simulator.
class LocationService {
  LocationService({required this.onPosition, required this.onStatus});

  final ValueChanged<GeoPoint> onPosition;
  final ValueChanged<String> onStatus;

  StreamSubscription<Position>? _sub;
  GeoPoint? _lastReal;
  GeoPoint? _virtual;
  bool _simulated = false;

  bool get simulated => _simulated;
  GeoPoint? get lastReal => _lastReal;
  bool gpsAvailable = false;

  /// Requests permission and starts streaming. Returns false if GPS is unavailable.
  Future<bool> startReal() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        onStatus('Location services are off');
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        onStatus('Location permission denied');
        return false;
      }
      gpsAvailable = true;
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 1),
      ).listen(
        (p) {
          _lastReal = GeoPoint(p.latitude, p.longitude);
          if (!_simulated) onPosition(_lastReal!);
        },
        onError: (Object e) => onStatus('GPS error: $e'),
      );
      return true;
    } catch (e) {
      onStatus('GPS unavailable: $e');
      return false;
    }
  }

  /// Switches to virtual movement, starting at [start].
  void enableSimulation(GeoPoint start) {
    _simulated = true;
    _virtual = start;
    onPosition(start);
  }

  void disableSimulation() {
    _simulated = false;
    if (_lastReal != null) onPosition(_lastReal!);
  }

  void moveVirtual(double northMeters, double eastMeters) {
    if (!_simulated || _virtual == null) return;
    _virtual = GeoMath.moveNE(_virtual!, northMeters, eastMeters);
    onPosition(_virtual!);
  }

  void moveVirtualAlong(double bearingDeg, double meters) {
    if (!_simulated || _virtual == null) return;
    _virtual = GeoMath.offset(_virtual!, bearingDeg, meters);
    onPosition(_virtual!);
  }

  void teleportVirtual(GeoPoint p) {
    if (!_simulated) return;
    _virtual = p;
    onPosition(p);
  }

  void dispose() => _sub?.cancel();
}
