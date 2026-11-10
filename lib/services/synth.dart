import 'dart:math' as math;
import 'dart:typed_data';

/// Tiny offline PCM synthesizer. Every sound in the game is rendered here into
/// an in-memory 16-bit mono WAV, so the app ships with zero audio assets.
class Synth {
  Synth._();

  static const int sampleRate = 44100;
  static final math.Random _noise = math.Random(7);

  // ---------------------------------------------------------------- waves

  static double sine(double phase) => math.sin(2 * math.pi * phase);

  static double triangle(double phase) {
    final p = phase - phase.floorToDouble();
    return 4 * (p < 0.5 ? p : 1 - p) - 1;
  }

  static double saw(double phase) {
    final p = phase - phase.floorToDouble();
    return 2 * p - 1;
  }

  // ---------------------------------------------------------------- sounds

  /// Beacon ping for a relic chord. [brightness] 0..1 controls how many
  /// harmonics are present and where the low-pass filter sits: 1 = crisp and
  /// glassy (facing the relic), 0 = muffled thump (facing away).
  static Uint8List beaconPing(List<double> chord, double brightness, {int durationMs = 420}) {
    final n = _len(durationMs);
    final out = Float64List(n);
    final harmonics = 1 + (brightness * 9).round();
    for (var c = 0; c < chord.length; c++) {
      final f = chord[c];
      final toneAmp = c == 0 ? 1.0 : 0.45;
      for (var h = 1; h <= harmonics; h++) {
        final hf = f * h;
        if (hf > sampleRate / 2.2) break;
        // Odd harmonics stronger: somewhere between square and saw.
        final amp = toneAmp / h * (h.isOdd ? 1.0 : 0.55);
        for (var i = 0; i < n; i++) {
          out[i] += amp * math.sin(2 * math.pi * hf * i / sampleRate);
        }
      }
      // Detuned shimmer layer appears only when well aligned.
      if (brightness > 0.7) {
        final shimmer = (brightness - 0.7) / 0.3 * 0.25 * toneAmp;
        for (var i = 0; i < n; i++) {
          out[i] += shimmer * math.sin(2 * math.pi * f * 2.003 * i / sampleRate);
        }
      }
    }
    final cutoff = 350 + brightness * brightness * 7500;
    _lowPass(out, cutoff);
    _envelope(out, attackMs: 4, decayRate: 6.5);
    return _toWav(out, peak: 0.85);
  }

  // ---------------------------------------------------------------- boom-bap kit
  //
  // Old-school drum-machine flavour: long 808-style kick, crunchy snare and
  // tight hats, all run through a 12-bit / ~26 kHz crusher for that dusty
  // late-80s sampler grit. Everything is synthesized from scratch.

  /// Deep boomy kick: sine with a fast pitch drop and a soft-clipped tail.
  static Uint8List boomKick() => _toWav(boomKickPcm(), peak: 0.95);

  static Float64List boomKickPcm() {
    final n = _len(480);
    final out = Float64List(n);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final f = 46 + 110 * math.exp(-t * 28);
      phase += f / sampleRate;
      final body = sine(phase) * math.exp(-t * 5.5);
      final click = (_noise.nextDouble() * 2 - 1) * math.exp(-t * 900) * 0.4;
      out[i] = _tanh((body + click) * 1.8);
    }
    _crush(out);
    _fadeOut(out, 20);
    return out;
  }

  /// Cracking snare: tuned body + filtered noise with a short room tail.
  static Uint8List boomSnare() => _toWav(boomSnarePcm(), peak: 0.9);

  static Float64List boomSnarePcm() {
    final n = _len(260);
    final out = Float64List(n);
    var lp = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final tone = (sine(185 * t) * 0.6 + sine(330 * t) * 0.3) * math.exp(-t * 28);
      final white = _noise.nextDouble() * 2 - 1;
      lp += 0.25 * (white - lp);
      final noise = (white - lp) * math.exp(-t * 14); // crude high-pass
      out[i] = _tanh((tone + noise * 0.9) * 1.6);
    }
    _crush(out);
    _fadeOut(out, 15);
    return out;
  }

  /// Hi-hat. [open] gives a longer sizzle for the bar-end accent.
  static Uint8List boomHat({bool open = false}) => _toWav(boomHatPcm(open: open), peak: 0.7);

  static Float64List boomHatPcm({bool open = false}) {
    final n = _len(open ? 240 : 55);
    final out = Float64List(n);
    var lp = 0.0;
    final decay = open ? 13.0 : 75.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final white = _noise.nextDouble() * 2 - 1;
      lp += 0.6 * (white - lp);
      // Metallic ring from a few inharmonic square partials.
      var metal = 0.0;
      for (final f in const [3150.0, 4720.0, 6140.0, 7930.0]) {
        metal += (math.sin(2 * math.pi * f * t) >= 0 ? 1 : -1) * 0.12;
      }
      out[i] = ((white - lp) * 0.8 + metal) * math.exp(-t * decay);
    }
    _crush(out);
    _fadeOut(out, 5);
    return out;
  }

  /// Warm, slightly overdriven bass note (sine + 2nd harmonic).
  static Uint8List boomBass(double hz, {int durationMs = 340}) => _toWav(boomBassPcm(hz, durationMs: durationMs), peak: 0.85);

  static Float64List boomBassPcm(double hz, {int durationMs = 340}) {
    final n = _len(durationMs);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.min(1.0, i / 120) * math.exp(-t * 4);
      out[i] = _tanh((sine(hz * t) + 0.35 * sine(hz * 2 * t) + 0.1 * triangle(hz * 3 * t)) * 1.4) * env;
    }
    _lowPass(out, 900);
    _fadeOut(out, 25);
    return out;
  }

  /// Rising synth stab for each excavation shake. [step] 0..4.
  static Uint8List excavationRise(double rootHz, int step) {
    final n = _len(260);
    final out = Float64List(n);
    final start = rootHz * math.pow(2, step / 5);
    final end = start * 1.5;
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final f = start + (end - start) * t * t;
      phase += f / sampleRate;
      out[i] = 0.6 * saw(phase) + 0.4 * triangle(phase * 1.005);
    }
    // Filter sweep that opens as the note rises.
    _lowPassSweep(out, 600 + step * 400.0, 4000 + step * 1500.0);
    _envelope(out, attackMs: 8, decayRate: 5);
    return _toWav(out, peak: 0.8);
  }

  /// Celebratory pentatonic arpeggio + held chord when a relic is unearthed.
  static Uint8List arpeggio(double rootHz) {
    const ratios = [1.0, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2.0, 9 / 4, 5 / 2, 3.0];
    const noteMs = 95;
    final total = _len(noteMs * ratios.length + 1100);
    final out = Float64List(total);
    for (var k = 0; k < ratios.length; k++) {
      final start = _len(noteMs * k);
      final f = rootHz * ratios[k];
      final len = _len(450);
      for (var i = 0; i < len && start + i < total; i++) {
        final t = i / sampleRate;
        final env = (i < 200 ? i / 200 : 1.0) * math.exp(-t * 7);
        final ph = f * t;
        out[start + i] += 0.35 * env * (0.7 * triangle(ph) + 0.3 * saw(ph * 2));
      }
    }
    // Final sustained major chord.
    final chordStart = _len(noteMs * ratios.length);
    for (final r in const [2.0, 2.5, 3.0, 4.0]) {
      final f = rootHz * r;
      for (var i = 0; chordStart + i < total; i++) {
        final t = i / sampleRate;
        final env = math.min(1.0, i / 600) * math.exp(-t * 2.2);
        out[chordStart + i] += 0.22 * env * (sine(f * t) + 0.3 * sine(f * 2 * t));
      }
    }
    _lowPass(out, 6000);
    return _toWav(out, peak: 0.85);
  }

  // ---------------------------------------------------------------- dsp

  static int _len(int ms) => (sampleRate * ms / 1000).round();

  static double _tanh(double x) {
    final e = math.exp(2 * x.clamp(-10.0, 10.0));
    return (e - 1) / (e + 1);
  }

  /// 12-bit, ~26 kHz sample-and-hold crusher: classic sampler grit.
  static void _crush(Float64List s, {int bits = 12, int hold = 2}) {
    final levels = math.pow(2, bits - 1).toDouble();
    var held = 0.0;
    for (var i = 0; i < s.length; i++) {
      if (i % hold == 0) held = (s[i] * levels).round() / levels;
      s[i] = held;
    }
  }

  static void _fadeOut(Float64List s, int ms) {
    final f = math.min(_len(ms), s.length);
    for (var i = 0; i < f; i++) {
      s[s.length - 1 - i] *= i / f;
    }
  }

  static void lowPass(Float64List s, double cutoff) => _lowPass(s, cutoff);

  static void _lowPass(Float64List s, double cutoff) {
    final dt = 1 / sampleRate;
    final rc = 1 / (2 * math.pi * cutoff);
    final a = dt / (rc + dt);
    var y = 0.0;
    // Two cascaded one-pole stages for a steeper 12 dB/oct slope.
    var y2 = 0.0;
    for (var i = 0; i < s.length; i++) {
      y += a * (s[i] - y);
      y2 += a * (y - y2);
      s[i] = y2;
    }
  }

  static void _lowPassSweep(Float64List s, double from, double to) {
    final dt = 1 / sampleRate;
    var y = 0.0;
    for (var i = 0; i < s.length; i++) {
      final cutoff = from + (to - from) * i / s.length;
      final rc = 1 / (2 * math.pi * cutoff);
      final a = dt / (rc + dt);
      y += a * (s[i] - y);
      s[i] = y;
    }
  }

  static void _envelope(Float64List s, {required double attackMs, required double decayRate}) {
    final attack = _len(attackMs.round()).clamp(1, s.length);
    final fadeOut = math.min(_len(15), s.length);
    for (var i = 0; i < s.length; i++) {
      var env = i < attack ? i / attack : math.exp(-(i - attack) / sampleRate * decayRate);
      if (i > s.length - fadeOut) env *= (s.length - i) / fadeOut;
      s[i] *= env;
    }
  }

  static Uint8List toWav(Float64List samples, {double peak = 0.9}) => _toWav(samples, peak: peak);

  static Uint8List _toWav(Float64List samples, {double peak = 0.9}) {
    var max = 1e-9;
    for (final v in samples) {
      final a = v.abs();
      if (a > max) max = a;
    }
    final gain = peak / max;
    final dataLen = samples.length * 2;
    final bytes = ByteData(44 + dataLen);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // PCM chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM format
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bytes.setUint16(32, 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // bits per sample
    str(36, 'data');
    bytes.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * gain).clamp(-1.0, 1.0);
      bytes.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
