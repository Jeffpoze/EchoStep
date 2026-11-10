import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../config.dart';
import '../models/radar_reading.dart';
import '../models/relic.dart';
import '../utils/geo_math.dart';
import 'synth.dart';

/// Computes the radar reading, runs the Geiger-counter haptics and plays
/// the excavation one-shots. The music itself lives in [StemEngine].
class AudioRadarService {
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, Future<AudioSource?>> _cache = {};

  bool _audioReady = false;
  bool muted = false;
  bool _running = false;

  Timer? _geigerTimer;

  // Latest inputs from the game controller.
  RadarReading? _reading;
  GamePhase _phase = GamePhase.locating;

  bool get audioReady => _audioReady;

  // ------------------------------------------------------------ radar math

  /// Nearest uncollected relic relative to [user] facing [heading].
  static RadarReading? computeReading(GeoPoint user, double heading, List<Relic> relics) {
    RadarReading? best;
    for (final r in relics) {
      if (r.collected) continue;
      final d = GeoMath.distance(user, r.position);
      if (best != null && d >= best.distance) continue;
      final b = GeoMath.bearing(user, r.position);
      best = RadarReading(target: r, distance: d, bearing: b, angleDelta: GeoMath.signedDelta(heading, b));
    }
    return best;
  }

  /// Geiger interval: 2000ms at >=200m, linearly down to 150ms at 15m.
  static int geigerIntervalMs(double distance) {
    final t = ((distance - kGeigerNearMeters) / (kGeigerFarMeters - kGeigerNearMeters)).clamp(0.0, 1.0);
    return (kGeigerFastMs + (kGeigerSlowMs - kGeigerFastMs) * t).round();
  }


  // ------------------------------------------------------------ lifecycle

  Future<void> init() async {
    try {
      if (!_soloud.isInitialized) await _soloud.init();
      _audioReady = true;
    } catch (e) {
      debugPrint('Audio engine unavailable, continuing silently: $e');
      _audioReady = false;
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    _scheduleGeiger();
  }

  void update({required RadarReading? reading, required GamePhase phase}) {
    _reading = reading;
    _phase = phase;
  }

  void dispose() {
    _running = false;
    _geigerTimer?.cancel();
    if (_audioReady) _soloud.deinit();
  }

  // ------------------------------------------------------------ loops

  void _scheduleGeiger() {
    if (!_running) return;
    final reading = _reading;
    final active = reading != null && _phase == GamePhase.hunting;
    final ms = active ? geigerIntervalMs(reading.distance) : 500;
    _geigerTimer = Timer(Duration(milliseconds: ms), () {
      if (active) HapticFeedback.lightImpact();
      _scheduleGeiger();
    });
  }

  // ------------------------------------------------------------ one-shots

  void playExcavationHit(Relic relic, int step) {
    _play('rise_${relic.soundKey}_$step', () => Synth.excavationRise(relic.note.frequency / 2, step), volume: 0.8);
  }

  void playUnlockArpeggio(Relic relic) {
    _play('arp_${relic.note.name}', () => Synth.arpeggio(relic.note.frequency / 2), volume: 0.9);
  }

  // ------------------------------------------------------------ helpers

  void _play(String key, Uint8List Function() build, {double volume = 1}) {
    if (muted || !_audioReady) return;
    _source(key, build).then((src) {
      if (src == null) return;
      try {
        _soloud.play(src, volume: volume);
      } catch (e) {
        debugPrint('play $key failed: $e');
      }
    });
  }

  Future<AudioSource?> _source(String key, Uint8List Function() build) {
    if (!_audioReady) return Future.value(null);
    return _cache.putIfAbsent(key, () async {
      try {
        return await _soloud.loadMem('$key.wav', build());
      } catch (e) {
        debugPrint('Failed to load synthesized $key: $e');
        _cache.remove(key);
        return null;
      }
    });
  }
}
