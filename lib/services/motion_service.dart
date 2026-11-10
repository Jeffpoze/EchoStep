import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../config.dart';

/// Step cadence (BPM) + shake detection from the gravity-free accelerometer.
class MotionService {
  MotionService({required this.onStep, required this.onShake, required this.onCadenceChanged});

  /// Fired on each detected (or simulated) footstep.
  final VoidCallback onStep;

  /// Fired on a sharp shake, only while [shakeDetectionEnabled].
  final VoidCallback onShake;

  final ValueChanged<double> onCadenceChanged;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  Timer? _decayTimer;
  Timer? _simWalkTimer;

  /// Only true when the player is inside the Excavation Zone.
  bool shakeDetectionEnabled = false;

  double _smoothed = 0;
  double _prev = 0;
  double _prevPrev = 0;
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);
  final Queue<DateTime> _stepTimes = Queue();

  double _bpm = 0;
  double get bpm => _bpm;

  /// Time of the most recent (real or simulated) footstep.
  DateTime get lastStepAt => _lastStep;

  bool sensorAvailable = true;
  bool get simulatingWalk => _simWalkTimer != null;

  void start() {
    _sub = userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      _onAccel,
      onError: (Object e) {
        sensorAvailable = false;
        debugPrint('Accelerometer unavailable: $e');
      },
      cancelOnError: true,
    );
    _decayTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _decayCadence());
  }

  void _onAccel(UserAccelerometerEvent e) {
    final now = DateTime.now();
    final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    // Shake detector uses the raw magnitude so short spikes aren't smoothed away.
    if (shakeDetectionEnabled &&
        magnitude > kShakeThreshold &&
        now.difference(_lastShake) > kShakeDebounce) {
      _lastShake = now;
      onShake();
    }

    if (simulatingWalk) return; // simulated cadence owns the step clock

    // Peak detector on a lightly low-passed signal.
    _smoothed = _smoothed * 0.6 + magnitude * 0.4;
    final isPeak = _prev > kStepThreshold && _prev > _prevPrev && _prev >= _smoothed;
    if (isPeak && now.difference(_lastStep) >= kStepDebounce && magnitude < kShakeThreshold) {
      _registerStep(now);
    }
    _prevPrev = _prev;
    _prev = _smoothed;
  }

  void _registerStep(DateTime now) {
    if (now.difference(_lastStep) > const Duration(milliseconds: 2000)) {
      _stepTimes.clear(); // stride broken; start a fresh window
    }
    _lastStep = now;
    _stepTimes.addLast(now);
    while (_stepTimes.length > 8) {
      _stepTimes.removeFirst();
    }
    if (_stepTimes.length >= 3) {
      final spanMs = _stepTimes.last.difference(_stepTimes.first).inMilliseconds;
      final avg = spanMs / (_stepTimes.length - 1);
      _setBpm(60000 / avg);
    }
    onStep();
  }

  void _decayCadence() {
    if (_bpm > 0 && DateTime.now().difference(_lastStep) > const Duration(milliseconds: 2500)) {
      _stepTimes.clear();
      _setBpm(0);
    }
  }

  void _setBpm(double v) {
    final clamped = v.clamp(0.0, 220.0).toDouble();
    if ((clamped - _bpm).abs() < 0.5) return;
    _bpm = clamped;
    onCadenceChanged(_bpm);
  }

  /// Desk simulator: inject footsteps at a fixed cadence.
  void setSimulatedWalking(bool enabled, {double bpm = kSimWalkBpm}) {
    _simWalkTimer?.cancel();
    _simWalkTimer = null;
    _stepTimes.clear();
    if (enabled) {
      final interval = Duration(milliseconds: (60000 / bpm).round());
      _simWalkTimer = Timer.periodic(interval, (_) => _registerStep(DateTime.now()));
    }
  }

  void dispose() {
    _sub?.cancel();
    _decayTimer?.cancel();
    _simWalkTimer?.cancel();
  }
}
