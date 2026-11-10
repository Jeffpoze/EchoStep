import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../config.dart';
import '../models/radar_reading.dart';
import '../models/relic.dart';
import '../utils/geo_math.dart';
import 'synth.dart';

/// Computes the radar reading, drives the procedural audio loop and the
/// Geiger-counter haptics.
class AudioRadarService {
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, Future<AudioSource?>> _cache = {};

  bool _audioReady = false;
  bool muted = false;
  bool _running = false;

  Timer? _beatTimer;
  Timer? _geigerTimer;

  // Latest inputs from the game controller.
  RadarReading? _reading;
  double _stepBpm = 0;
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

  /// Beat tempo follows walking cadence, idling at 80 BPM when still.
  double get tempoBpm => _stepBpm >= 40 ? _stepBpm : kIdleBpm;

  // ------------------------------------------------------------ lifecycle

  Future<void> init() async {
    try {
      if (!_soloud.isInitialized) await _soloud.init();
      _audioReady = true;
      // Pre-render the drum kit so the first bar lands on time.
      await Future.wait([
        _source('kick', Synth.boomKick),
        _source('snare', Synth.boomSnare),
        _source('hat', Synth.boomHat),
        _source('hat_open', () => Synth.boomHat(open: true)),
      ]);
    } catch (e) {
      debugPrint('Audio engine unavailable, continuing silently: $e');
      _audioReady = false;
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    _scheduleBeat();
    _scheduleGeiger();
  }

  void update({required RadarReading? reading, required double stepBpm, required GamePhase phase}) {
    _reading = reading;
    _stepBpm = stepBpm;
    _phase = phase;
  }

  /// Pre-render ping variants for a relic so the first beats aren't late.
  void prewarm(Relic relic) {
    for (var b = 0; b <= 5; b++) {
      unawaited(_pingSource(relic, b));
    }
  }

  void dispose() {
    _running = false;
    _beatTimer?.cancel();
    _geigerTimer?.cancel();
    if (_audioReady) _soloud.deinit();
  }

  // ------------------------------------------------------------ loops

  // Boom-bap sequencer: one bar = 16 sixteenth-notes, tempo = walking cadence.
  //                       0 1 2 3 4 5 6 7 8 9 A B C D E F
  static const _kick  = {0, 7, 10};             // "boom"
  static const _kickB = {0, 7, 10, 13};         // variation on odd bars
  static const _snare = {4, 12};                // "bap" on 2 and 4
  static const _bassSteps = {0: 1.0, 7: 1.0, 10: 1.5, 14: 16 / 9}; // root, root, fifth, b7
  static const double _swing = 0.17;            // ~58% MPC-style shuffle on odd 16ths

  final Stopwatch _clock = Stopwatch();
  double _nextStepMs = 0;
  int _step = 0;
  int _bar = 0;

  void _scheduleBeat() {
    if (!_running) return;
    if (!_clock.isRunning) _clock.start();
    final now = _clock.elapsedMicroseconds / 1000.0;
    // If we fell badly behind (app paused, debugger), resync instead of bursting.
    if (now - _nextStepMs > 250) _nextStepMs = now;
    final delay = (_nextStepMs - now).clamp(0.0, 1000.0);
    _beatTimer = Timer(Duration(microseconds: (delay * 1000).round()), () {
      final stepMs = 60000 / tempoBpm / 4;
      final step = _step;
      if (step.isOdd) {
        // Swing: push the off-16ths late for that lazy head-nod feel.
        Timer(Duration(microseconds: (stepMs * _swing * 1000).round()), () => _onStep(step));
      } else {
        _onStep(step);
      }
      _step = (_step + 1) % 16;
      if (_step == 0) _bar++;
      _nextStepMs += stepMs; // tempo re-evaluated every 16th
      _scheduleBeat();
    });
  }

  void _onStep(int step) {
    if (muted || !_audioReady) return;
    final reading = _reading;
    final hunting = reading != null && _phase == GamePhase.hunting;
    final drumGain = _phase == GamePhase.excavating ? 0.6 : 1.0;

    // Drums
    if ((_bar.isOdd ? _kickB : _kick).contains(step)) {
      _play('kick', Synth.boomKick, volume: 0.8 * drumGain);
    }
    if (_snare.contains(step)) {
      _play('snare', Synth.boomSnare, volume: 0.55 * drumGain);
    }
    if (step == 14) {
      _play('hat_open', () => Synth.boomHat(open: true), volume: 0.2 * drumGain);
    } else if (step.isEven) {
      _play('hat', Synth.boomHat, volume: (step % 4 == 0 ? 0.22 : 0.15) * drumGain);
    }

    if (!hunting) return;
    final closeness = reading.closeness;

    // Bass line in the key of the relic you're tracking.
    final ratio = _bassSteps[step];
    if (ratio != null) {
      var root = reading.target.note.frequency;
      while (root > 110) {
        root /= 2;
      }
      final hz = root * ratio;
      _play('bass_${hz.round()}', () => Synth.boomBass(hz), volume: 0.3 + 0.35 * closeness);
    }

    // Beacon ping as the melodic hook: half notes far away, quarter notes when close.
    final pingSteps = closeness > 0.6 ? const {0, 4, 8, 12} : const {0, 8};
    if (pingSteps.contains(step)) _playPing(reading);
  }

  void _playPing(RadarReading reading) {
    final bucket = (reading.brightness * 5).round();
    final closeness = reading.closeness;
    final volume = 0.12 + 0.88 * closeness;
    // Spatial cue: pan toward the side the relic is on.
    final pan = (reading.angleDelta / 90).clamp(-1.0, 1.0) * 0.8;
    _pingSource(reading.target, bucket).then((src) {
      if (src == null || muted) return;
      try {
        final h = _soloud.play(src, volume: volume, pan: pan);
        // Pitch rises (up to a fifth) as the relic gets closer.
        _soloud.setRelativePlaySpeed(h, 1.0 + 0.5 * closeness);
      } catch (e) {
        debugPrint('ping failed: $e');
      }
    });
  }

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

  Future<AudioSource?> _pingSource(Relic relic, int bucket) =>
      _source('ping_${relic.soundKey}_$bucket', () => Synth.beaconPing(relic.chord, bucket / 5));

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
