import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/radar_reading.dart';
import '../models/relic.dart';
import '../services/audio_radar_service.dart';
import '../services/heading_service.dart';
import '../services/location_service.dart';
import '../services/motion_service.dart';
import '../services/relic_spawner_service.dart';
import '../services/stem_engine.dart';
import '../utils/geo_math.dart';

/// Central game state. Owns every service and exposes a single
/// [ChangeNotifier] for the UI.
class GameController extends ChangeNotifier {
  GameController() {
    _motion = MotionService(onStep: _onStep, onShake: _onShake, onCadenceChanged: (_) => _changed());
    _location = LocationService(onPosition: _onPosition, onStatus: _onStatus);
    _heading = HeadingService(onHeading: (_) => _recompute());
  }

  final RelicSpawnerService _spawner = RelicSpawnerService();
  final AudioRadarService audio = AudioRadarService();
  final StemEngine stems = StemEngine();
  late final MotionService _motion;
  late final LocationService _location;
  late final HeadingService _heading;

  // ------------------------------------------------------------ state
  GamePhase phase = GamePhase.locating;
  GeoPoint? userPosition;
  List<Relic> relics = [];
  final List<Relic> inventory = [];

  /// Recent footprints (oldest first), dropped every ~2.5 m of travel.
  final List<GeoPoint> trail = [];
  static const int _maxTrail = 60;
  RadarReading? reading;
  Relic? excavationTarget;
  double excavationProgress = 0;
  String? statusMessage;
  Relic? lastUnlocked;

  bool simulatorMode = false;
  bool simWalking = false;

  double get stepBpm => _motion.bpm;
  double get heading => _heading.heading;
  /// Loop tempo the stems are currently playing at.
  double get tempoBpm => StemEngine.stemBpm * stems.playbackRate;
  bool get muted => audio.muted;
  bool get hasCompass => _heading.hasSensor || simulatorMode;
  bool get gpsAvailable => _location.gpsAvailable;

  bool _disposed = false;
  Timer? _bannerTimer;

  // ------------------------------------------------------------ lifecycle

  Future<void> init() async {
    await audio.init();
    unawaited(stems.start());
    _motion.start();
    _heading.start();
    audio.start();
    final ok = await _location.startReal();
    if (!ok) {
      // No GPS (desk, emulator, denied permission): drop straight into the simulator.
      setSimulatorMode(true);
    } else {
      // If no fix arrives soon, let the player know the simulator exists.
      Timer(const Duration(seconds: 8), () {
        if (userPosition == null && !_disposed) {
          _onStatus('Waiting for GPS… enable Desk Simulator to play indoors');
        }
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _bannerTimer?.cancel();
    _motion.dispose();
    _location.dispose();
    _heading.dispose();
    stems.dispose();
    audio.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ inputs

  void _onPosition(GeoPoint p) {
    final prev = userPosition;
    // A D-pad hop or teleport (>25 m) isn't walking: start a fresh trail.
    if (prev != null && GeoMath.distance(prev, p) > 25) trail.clear();
    if (trail.isEmpty || GeoMath.distance(trail.last, p) >= 2.5) {
      trail.add(p);
      if (trail.length > _maxTrail) trail.removeAt(0);
    }
    userPosition = p;
    if (relics.isEmpty) respawnRelics();
    _recompute();
  }

  void _onStatus(String msg) {
    statusMessage = msg;
    _changed();
  }

  void _onStep() {
    // In the simulator, footsteps actually move the player along their heading.
    if (simulatorMode && simWalking) {
      _location.moveVirtualAlong(heading, kSimStrideMeters);
    }
    _changed();
  }

  void _onShake() {
    if (phase != GamePhase.excavating || excavationTarget == null) return;
    excavationProgress = (excavationProgress + kShakeProgressPerHit).clamp(0.0, 1.0);
    final step = (excavationProgress / kShakeProgressPerHit).round() - 1;
    HapticFeedback.heavyImpact();
    stems.onShake();
    audio.playExcavationHit(excavationTarget!, step.clamp(0, 4));
    if (excavationProgress >= 0.999) {
      _unlock(excavationTarget!);
    }
    _changed();
  }

  // ------------------------------------------------------------ game logic

  void respawnRelics() {
    final origin = userPosition;
    if (origin == null) return;
    relics = _spawner.spawnAround(origin);
    excavationTarget = null;
    excavationProgress = 0;
    phase = GamePhase.hunting;
    _recompute();
  }

  void _recompute() {
    final pos = userPosition;
    if (pos == null) {
      _changed();
      return;
    }
    reading = AudioRadarService.computeReading(pos, heading, relics);

    if (relics.isNotEmpty && relics.every((r) => r.collected)) {
      phase = GamePhase.allCollected;
    } else if (phase == GamePhase.excavating) {
      final t = excavationTarget;
      if (t == null || GeoMath.distance(pos, t.position) > kExcavationExitRadius) {
        // Walked away mid-dig: abandon progress.
        excavationTarget = null;
        excavationProgress = 0;
        phase = GamePhase.hunting;
      }
    } else if (reading != null && reading!.distance <= kExcavationRadius) {
      phase = GamePhase.excavating;
      excavationTarget = reading!.target;
      excavationProgress = 0;
      HapticFeedback.mediumImpact();
      // A real seeker stops to dig; do the same for the simulated walker.
      if (simWalking) setSimWalking(false);
    } else if (phase != GamePhase.allCollected || relics.any((r) => !r.collected)) {
      phase = GamePhase.hunting;
    }

    _motion.shakeDetectionEnabled = phase == GamePhase.excavating;
    audio.update(reading: reading, phase: phase);
    _pushMix();
    _changed();
  }

  void _unlock(Relic relic) {
    relic.collected = true;
    relic.collectedAt = DateTime.now();
    inventory.add(relic);
    lastUnlocked = relic;
    audio.playUnlockArpeggio(relic);
    excavationTarget = null;
    excavationProgress = 0;
    phase = GamePhase.hunting;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      lastUnlocked = null;
      _changed();
    });
    _recompute();
  }

  // ------------------------------------------------------------ UI actions

  void toggleMute() {
    audio.muted = !audio.muted;
    stems.setMuted(audio.muted);
    _changed();
  }

  void setSimulatorMode(bool on) {
    simulatorMode = on;
    if (on) {
      _location.enableSimulation(userPosition ?? _location.lastReal ?? const GeoPoint(kDefaultLat, kDefaultLng));
      _heading.setSimulatedHeading(_heading.heading);
      _heading.setSimulated(true);
      statusMessage = null;
    } else {
      setSimWalking(false);
      _heading.setSimulated(false);
      _location.disableSimulation();
      if (!_location.gpsAvailable) {
        statusMessage = 'No GPS available — Desk Simulator recommended';
      }
    }
    _recompute();
  }

  void simMove(double northMeters, double eastMeters) {
    _location.moveVirtual(northMeters, eastMeters);
  }

  void setSimHeading(double deg) => _heading.setSimulatedHeading(deg);

  void setSimWalking(bool on) {
    simWalking = on;
    _motion.setSimulatedWalking(on);
    _changed();
  }

  void simulateShake() => _onShake();

  /// Desk helper: jump to ~20m from the nearest relic.
  void simJumpNearTarget() {
    final r = reading;
    final pos = userPosition;
    if (!simulatorMode || r == null || pos == null) return;
    final back = GeoMath.normalize360(r.bearing + 180);
    _location.teleportVirtual(GeoMath.offset(r.target.position, back, 20));
  }

  void _pushMix() => stems.update(
        stepBpm: _motion.bpm,
        reading: reading,
        phase: phase,
        excavationProgress: excavationProgress,
      );

  void _changed() {
    _pushMix(); // cadence/progress changes reach the mixer even without a GPS fix
    if (!_disposed) notifyListeners();
  }
}
