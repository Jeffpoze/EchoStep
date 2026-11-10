import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/radar_reading.dart';
import 'stem_synth.dart';

/// The four Suno stems, mixed live from walking and radar data.
enum Stem {
  idleAmbient('idle_ambient', 'Idle Ambient'),
  walkGroove('walk_groove', 'Walk Groove'),
  radarMelody('radar_melody', 'Radar Melody'),
  excavateHype('excavate_hype', 'Excavate Hype');

  const Stem(this.fileBase, this.label);
  final String fileBase;
  final String label;

  /// Stems that run through a low-pass biquad.
  bool get filtered => this == Stem.radarMelody || this == Stem.excavateHype;
}

enum TakeOrigin { bundled, picked, synth }

/// One playable take (version) of a stem.
class StemTake {
  StemTake({required this.label, required this.source, required this.origin, required this.length});
  final String label;
  final AudioSource source;
  final TakeOrigin origin;
  final Duration length;
}

/// Hybrid Suno-stem + procedural engine.
///
/// * All four stems start in the same audio frame (a SoLoud voice group is
///   unpaused in one call), so they stay phase-locked.
/// * Each stem has its own gain; radar and excavate also run through their
///   own low-pass biquad, and radar has its own stereo pan.
/// * When a stem has two takes (`name.mp3` and `name1.mp3`/`name2.mp3`), the
///   whole mix crossfades to the other take at the end of every loop.
/// * Any stem missing from `Song/` falls back to a synthesized 114 BPM loop.
class StemEngine extends ChangeNotifier {
  static const String assetDir = 'Song/';
  static const double stemBpm = kStemBpm; // 114
  static const Duration _xfade = Duration(milliseconds: 1800);
  static const Duration _ramp = Duration(milliseconds: 180);

  final SoLoud _soloud = SoLoud.instance;
  final Map<Stem, List<StemTake>> takes = {for (final s in Stem.values) s: <StemTake>[]};
  final Map<Stem, SoundHandle> _voices = {};
  final Set<int> _filterActivated = {};
  Map<String, Uint8List>? _fallbackWavs;
  final Map<Stem, List<StemTake>> _defaults = {};

  bool ready = false;
  bool muted = false;
  String status = 'Loading stems…';
  int cycle = 0;
  bool _switching = false;
  Stem? _referenceStem;
  Duration _cycleLength = Duration.zero;
  Timer? _tick;

  // Live inputs.
  double _stepBpm = 0;
  RadarReading? _reading;
  GamePhase _phase = GamePhase.locating;
  double _excavationProgress = 0;
  double _resonanceBoost = 0;

  /// Current target gains, exposed for the drawer's level meters.
  final Map<Stem, double> gains = {for (final s in Stem.values) s: 0};
  double playbackRate = 1;
  double radarCutoff = 250;

  // ------------------------------------------------------------ setup

  /// Loads bundled stems (or synth fallbacks) and starts playback. Assumes
  /// SoLoud is already initialized.
  Future<void> start() async {
    if (!_soloud.isInitialized) {
      status = 'Audio engine unavailable';
      notifyListeners();
      return;
    }
    try {
      await _loadBundledTakes();
      await _fillMissingWithSynth();
      for (final s in Stem.values) {
        _defaults[s] = List.of(takes[s]!);
      }
      ready = true;
      _startCycle(fadeIn: const Duration(milliseconds: 1200));
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
    } catch (e, st) {
      debugPrint('StemEngine failed: $e\n$st');
      status = 'Stem engine error: $e';
    }
    notifyListeners();
  }

  Future<void> _loadBundledTakes() async {
    List<String> assets;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      assets = manifest.listAssets().where((a) => a.startsWith(assetDir)).toList();
    } catch (_) {
      assets = const [];
    }
    for (final stem in Stem.values) {
      // Matches name.mp3, name1.mp3, name2.mp3… ; the plain name sorts first.
      final re = RegExp('^${RegExp.escape(assetDir)}${stem.fileBase}(\\d*)\\.mp3\$', caseSensitive: false);
      final matches = assets.where(re.hasMatch).toList()
        ..sort((a, b) {
          final na = int.tryParse(re.firstMatch(a)!.group(1)!) ?? 0;
          final nb = int.tryParse(re.firstMatch(b)!.group(1)!) ?? 0;
          return na.compareTo(nb);
        });
      for (final key in matches) {
        try {
          // Stream from disk: 4-minute songs would be ~80 MB each decoded.
          final src = await _soloud.loadAsset(key, mode: LoadMode.disk);
          takes[stem]!.add(StemTake(
            label: key.substring(assetDir.length),
            source: src,
            origin: TakeOrigin.bundled,
            length: _soloud.getLength(src),
          ));
        } catch (e) {
          debugPrint('Could not load $key: $e');
        }
      }
    }
  }

  Future<void> _fillMissingWithSynth() async {
    final missing = Stem.values.where((s) => takes[s]!.isEmpty).toList();
    if (missing.isEmpty) return;
    for (final stem in missing) {
      takes[stem]!.add(await _synthTake(stem));
    }
  }

  Future<StemTake> _synthTake(Stem stem) async {
    _fallbackWavs ??= await compute(renderFallbackStems, null);
    final src = await _soloud.loadMem('synth_${stem.fileBase}.wav', _fallbackWavs![stem.fileBase]!);
    return StemTake(
      label: 'synth fallback',
      source: src,
      origin: TakeOrigin.synth,
      length: _soloud.getLength(src),
    );
  }

  // ------------------------------------------------------------ playback

  StemTake currentTake(Stem s) {
    final list = takes[s]!;
    return list[cycle % list.length];
  }

  bool get _alternates => takes.values.any((l) => l.length > 1);

  void _startCycle({Duration fadeIn = _xfade}) {
    final old = Map<Stem, SoundHandle>.of(_voices);
    _voices.clear();

    // The longest current take defines the loop; everything shorter loops inside it.
    Stem ref = Stem.values.first;
    for (final s in Stem.values) {
      if (currentTake(s).length > currentTake(ref).length) ref = s;
    }
    _referenceStem = ref;
    _cycleLength = currentTake(ref).length;

    _computeTargets();
    final handles = <SoundHandle>[];
    for (final s in Stem.values) {
      final take = currentTake(s);
      if (s.filtered && _filterActivated.add(take.source.soundHash.hash)) {
        // Per-source filters must be activated before the voice is created.
        take.source.filters.biquadFilter.activate();
      }
      final h = _soloud.play(
        take.source,
        volume: 0,
        paused: true,
        // The reference stem plays once so its position marks the loop end.
        looping: !(_alternates && s == ref),
      );
      _soloud.setProtectVoice(h, true);
      _soloud.setRelativePlaySpeed(h, playbackRate);
      if (s.filtered) {
        final f = take.source.filters.biquadFilter;
        f.type(soundHandle: h).value = 0; // LOWPASS
        f.frequency(soundHandle: h).value = s == Stem.radarMelody ? radarCutoff : _excavateCutoff;
        f.resonance(soundHandle: h).value = s == Stem.radarMelody ? 0.8 : 2;
      }
      _voices[s] = h;
      handles.add(h);
    }

    // Sample-accurate synchronized start: unpause every stem in one call.
    final group = _soloud.createVoiceGroup();
    _soloud.addVoicesToGroup(group, handles);
    _soloud.setPause(group, false);
    _soloud.destroyVoiceGroup(group);

    for (final s in Stem.values) {
      _soloud.fadeVolume(_voices[s]!, muted ? 0 : gains[s]!, fadeIn);
    }
    for (final h in old.values) {
      _fadeOutAndStop(h, _xfade);
    }
    _switching = false;
    final labels = Stem.values.map((s) => currentTake(s).label).toSet().join(', ');
    status = _alternates ? 'Loop ${cycle + 1} · take ${String.fromCharCode(65 + cycle % 2)} · $labels' : labels;
    notifyListeners();
  }

  void _fadeOutAndStop(SoundHandle h, Duration d) {
    if (!_soloud.getIsValidVoiceHandle(h)) return;
    _soloud.fadeVolume(h, 0, d);
    _soloud.scheduleStop(h, d);
  }

  void _onTick() {
    if (!ready || _voices.isEmpty) return;
    _resonanceBoost *= 0.82; // shake resonance decays back down
    _computeTargets();

    for (final s in Stem.values) {
      final h = _voices[s]!;
      if (!_soloud.getIsValidVoiceHandle(h)) continue;
      _soloud.fadeVolume(h, muted ? 0 : gains[s]!, _ramp);
      // Same rate on every stem keeps them phase-locked while tracking cadence.
      _soloud.fadeRelativePlaySpeed(h, playbackRate, _ramp);
      final take = currentTake(s);
      if (s == Stem.radarMelody) {
        final f = take.source.filters.biquadFilter;
        f.frequency(soundHandle: h).fadeFilterParameter(to: radarCutoff, time: _ramp);
        _soloud.setPan(h, _radarPan);
      } else if (s == Stem.excavateHype) {
        final f = take.source.filters.biquadFilter;
        f.frequency(soundHandle: h).fadeFilterParameter(to: _excavateCutoff, time: _ramp);
        f.resonance(soundHandle: h).fadeFilterParameter(to: (2 + _resonanceBoost).clamp(0.1, 20), time: _ramp);
      }
    }

    // Alternate takes at the end of each loop.
    if (_alternates && !_switching) {
      final ref = _voices[_referenceStem]!;
      final atEnd = !_soloud.getIsValidVoiceHandle(ref) ||
          _soloud.getPosition(ref) >= _cycleLength - _xfade * playbackRate;
      if (atEnd) {
        _switching = true;
        cycle++;
        _startCycle();
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ mix rules

  void update({
    required double stepBpm,
    required RadarReading? reading,
    required GamePhase phase,
    required double excavationProgress,
  }) {
    _stepBpm = stepBpm;
    _reading = reading;
    _phase = phase;
    _excavationProgress = excavationProgress;
  }

  /// Each shake kicks the excavate filter's resonance up; it decays over ~1 s.
  void onShake() {
    _resonanceBoost = math.min(_resonanceBoost + 5, 17);
  }

  double get _excavateCutoff => 700 + 7300 * _excavationProgress;

  double get _radarPan {
    final r = _reading;
    if (r == null) return 0;
    return (r.angleDelta / 90).clamp(-1.0, 1.0) * 0.8;
  }

  void _computeTargets() {
    final bpm = _stepBpm;
    final walking = bpm >= 60;
    final r = _reading;
    final excavating = _phase == GamePhase.excavating;

    // 1. Idle ambient: full when still, ducks to 30% when walking.
    gains[Stem.idleAmbient] = walking ? 0.3 : 1.0;
    // 2. Walk groove: 0% at 60 BPM -> 100% at 114 BPM.
    gains[Stem.walkGroove] = ((bpm - 60) / (stemBpm - 60)).clamp(0.0, 1.0);
    // 3. Radar melody: proximity 300 m -> 15 m drives gain.
    gains[Stem.radarMelody] = r == null ? 0 : 0.05 + 0.95 * r.closeness;
    // 4. Excavate hype: in only inside the 15 m zone.
    gains[Stem.excavateHype] = excavating ? 1.0 : 0.0;

    // Cutoff 250 Hz (facing away) -> 8 kHz (within ±15°), exponential so the
    // sweep sounds even to the ear.
    radarCutoff = r == null ? 250 : 250 * math.pow(8000 / 250, r.brightness).toDouble();

    // Lock the loop tempo to cadence, within ±8% so it doesn't sound warped.
    playbackRate = walking ? (bpm / stemBpm).clamp(0.92, 1.08) : 1.0;
  }

  // ------------------------------------------------------------ audition

  /// Replaces [stem]'s takes with a local MP3 picked by the user and restarts
  /// the synced loop so you can hear it in context immediately.
  Future<void> auditionFile(Stem stem, {required String name, String? path, Uint8List? bytes}) async {
    try {
      final AudioSource src;
      if (path != null) {
        src = await _soloud.loadFile(path, mode: LoadMode.disk);
      } else if (bytes != null) {
        src = await _soloud.loadMem(name, bytes, mode: LoadMode.disk);
      } else {
        return;
      }
      takes[stem] = [
        StemTake(label: name, source: src, origin: TakeOrigin.picked, length: _soloud.getLength(src)),
      ];
      cycle = 0;
      _startCycle();
    } catch (e) {
      status = 'Could not load $name: $e';
      notifyListeners();
    }
  }

  /// Drops picked files and goes back to the bundled stems / synth fallback.
  void restoreDefaults() {
    if (!ready) return;
    for (final s in Stem.values) {
      takes[s] = List.of(_defaults[s]!);
    }
    cycle = 0;
    _startCycle();
  }

  void setMuted(bool m) {
    muted = m;
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
