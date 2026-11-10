import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
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
      _sub = Geolocator.getPositionStream(locationSettings: _walkSettings()).listen(
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

  /// GPS that keeps tracking with the screen locked (phone in your pocket).
  static LocationSettings _walkSettings() {
    const accuracy = LocationAccuracy.bestForNavigation;
    const distanceFilter = 1;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          // Blue status-bar pill while tracking in the background.
          showBackgroundLocationIndicator: true,
        );
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
          intervalDuration: const Duration(seconds: 1),
          // Android needs a foreground service (visible notification) to keep
          // GPS and the app alive while the screen is off.
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Sonic Seeker is hunting',
            notificationText: 'Tracking your walk to guide you to Sound Relics',
            notificationChannelName: 'Relic hunt',
            enableWakeLock: true,
            setOngoing: true,
            color: Color(0xFF00E5FF),
          ),
        );
      default:
        return const LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
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
