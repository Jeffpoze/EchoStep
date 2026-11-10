import 'dart:math' as math;
import 'dart:typed_data';

import 'synth.dart';

/// Procedural fallback stems, used for any Suno stem that isn't in `Song/`.
///
/// All four loops are exactly 4 bars at [kStemBpm] in C major pentatonic
/// (C – Am – F – G), so they're sample-identical in length and stay
/// phase-locked when started together.
const double kStemBpm = 114;
const int _bars = 4;
const int _sr = Synth.sampleRate;

double get _beatSec => 60 / kStemBpm;
int get _loopLen => (_bars * 4 * _beatSec * _sr).round();

// Per-bar harmony.
const _chordRoots = [65.41, 55.00, 87.31, 98.00]; // C2 A1 F2 G2 (bass)
const _padChords = [
  [130.81, 164.81, 196.00, 261.63], // C
  [110.00, 130.81, 164.81, 220.00], // Am
  [87.31, 130.81, 174.61, 220.00], // F
  [98.00, 146.83, 196.00, 246.94], // G
];
const _arpNotes = [
  [523.25, 659.25, 783.99, 880.00], // C E G A
  [440.00, 523.25, 659.25, 783.99], // A C E G
  [440.00, 523.25, 587.33, 783.99], // A C D G
  [392.00, 587.33, 659.25, 880.00], // G D E A
];

/// Renders all four fallback stems as WAV bytes. Top-level so it can run in
/// a background isolate via `compute`.
Map<String, Uint8List> renderFallbackStems(Object? _) => {
      'idle_ambient': Synth.toWav(_idleAmbient(), peak: 0.8),
      'walk_groove': Synth.toWav(_walkGroove(), peak: 0.9),
      'radar_melody': Synth.toWav(_radarMelody(), peak: 0.8),
      'excavate_hype': Synth.toWav(_excavateHype(), peak: 0.85),
    };

/// Adds [src] into the loop buffer starting at [at], wrapping past the end so
/// tails spill into the loop start (seamless looping).
void _mix(Float64List out, Float64List src, int at, double gain) {
  final n = out.length;
  for (var i = 0; i < src.length; i++) {
    out[(at + i) % n] += src[i] * gain;
  }
}

int _stepSample(int step16, {double swing = 0}) {
  final stepSec = _beatSec / 4;
  final t = step16 * stepSec + (step16.isOdd ? swing * stepSec : 0);
  return (t * _sr).round();
}

/// Warm detuned-saw pad with a slow filter breath and soft wind.
Float64List _idleAmbient() {
  final n = _loopLen;
  final out = Float64List(n);
  final barLen = n ~/ _bars;
  final rng = math.Random(11);
  for (var bar = 0; bar < _bars; bar++) {
    final start = bar * barLen;
    final len = barLen + (_sr * 0.6).round(); // overlap into the next chord
    for (final f in _padChords[bar]) {
      for (final detune in const [0.997, 1.003]) {
        var ph = rng.nextDouble();
        final voice = Float64List(len);
        for (var i = 0; i < len; i++) {
          ph += f * detune / _sr;
          final env = math.min(1.0, i / (_sr * 0.5)) * math.min(1.0, (len - i) / (_sr * 0.6));
          voice[i] = Synth.saw(ph) * env;
        }
        _mix(out, voice, start, 0.12);
      }
    }
  }
  Synth.lowPass(out, 1100);
  // Slow "breathing" swell (one cycle per loop keeps the seam clean).
  for (var i = 0; i < n; i++) {
    out[i] *= 0.75 + 0.25 * math.sin(2 * math.pi * i / n);
  }
  final wind = Float64List(n);
  for (var i = 0; i < n; i++) {
    wind[i] = rng.nextDouble() * 2 - 1;
  }
  Synth.lowPass(wind, 500);
  for (var i = 0; i < n; i++) {
    out[i] += wind[i] * 0.35;
  }
  return out;
}

/// The boom-bap groove: swung kick/snare/hats plus a bass line per chord.
Float64List _walkGroove() {
  final out = Float64List(_loopLen);
  final kick = Synth.boomKickPcm();
  final snare = Synth.boomSnarePcm();
  final hat = Synth.boomHatPcm();
  final openHat = Synth.boomHatPcm(open: true);
  const swing = 0.17;
  const bassSteps = {0: 1.0, 7: 1.0, 10: 1.5, 14: 16 / 9};
  for (var bar = 0; bar < _bars; bar++) {
    final kicks = bar.isOdd ? const {0, 7, 10, 13} : const {0, 7, 10};
    for (var s = 0; s < 16; s++) {
      final at = _stepSample(bar * 16 + s, swing: swing);
      if (kicks.contains(s)) _mix(out, kick, at, 0.9);
      if (s == 4 || s == 12) _mix(out, snare, at, 0.65);
      if (s == 14) {
        _mix(out, openHat, at, 0.22);
      } else if (s.isEven) {
        _mix(out, hat, at, s % 4 == 0 ? 0.25 : 0.17);
      }
      final ratio = bassSteps[s];
      if (ratio != null) _mix(out, Synth.boomBassPcm(_chordRoots[bar] * ratio), at, 0.5);
    }
  }
  return out;
}

/// Bright plucked pentatonic arpeggio in 8th notes. Left unfiltered on
/// purpose: the engine's low-pass does the "facing the relic" brightness.
Float64List _radarMelody() {
  final out = Float64List(_loopLen);
  const pattern = [0, 1, 2, 3, 2, 1, 2, 3];
  final pluckLen = (_sr * 0.4).round();
  for (var bar = 0; bar < _bars; bar++) {
    for (var k = 0; k < 8; k++) {
      final f = _arpNotes[bar][pattern[k]];
      final pluck = Float64List(pluckLen);
      for (var i = 0; i < pluckLen; i++) {
        final t = i / _sr;
        final env = math.min(1.0, i / 60) * math.exp(-t * 7);
        pluck[i] = env *
            (0.5 * Synth.saw(f * t) +
                0.3 * (Synth.sine(f * t) >= 0 ? 1 : -1) +
                0.2 * Synth.sine(f * 2.003 * t));
      }
      _mix(out, pluck, _stepSample(bar * 16 + k * 2), 0.5);
    }
  }
  return out;
}

/// Driving 16th-note saw stabs, claps on every beat and a rising sweep per bar.
Float64List _excavateHype() {
  final out = Float64List(_loopLen);
  final rng = math.Random(5);
  final stabLen = (_sr * _beatSec / 4 * 0.9).round();
  final barLen = _loopLen ~/ _bars;
  for (var bar = 0; bar < _bars; bar++) {
    final f = _chordRoots[bar] * 2;
    for (var s = 0; s < 16; s++) {
      final stab = Float64List(stabLen);
      final accent = s % 4 == 0 ? 1.0 : (s.isOdd ? 0.55 : 0.75);
      for (var i = 0; i < stabLen; i++) {
        final t = i / _sr;
        stab[i] = (Synth.saw(f * t) + 0.5 * Synth.saw(f * 1.5 * t)) * math.exp(-t * 18) * accent;
      }
      _mix(out, stab, _stepSample(bar * 16 + s), 0.35);
      if (s % 4 == 0) {
        final clap = Float64List((_sr * 0.12).round());
        for (var i = 0; i < clap.length; i++) {
          final t = i / _sr;
          // Three quick bursts = hand clap.
          final burst = t < 0.01 || (t > 0.012 && t < 0.02) || t > 0.024 ? 1.0 : 0.2;
          clap[i] = (rng.nextDouble() * 2 - 1) * burst * math.exp(-t * 30);
        }
        _mix(out, clap, _stepSample(bar * 16 + s), 0.45);
      }
    }
    // Riser: sine glide 200 Hz -> 1.2 kHz across the bar.
    final riser = Float64List(barLen);
    var ph = 0.0;
    for (var i = 0; i < barLen; i++) {
      final p = i / barLen;
      ph += (200 + 1000 * p * p) / _sr;
      riser[i] = Synth.sine(ph) * p * 0.5;
    }
    _mix(out, riser, bar * barLen, 0.3);
  }
  return out;
}
