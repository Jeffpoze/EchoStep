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

/// Which single song is playing.
enum MusicState { metronome, idle, walk, radar, excavate }

/// Walking within this distance of the nearest relic switches to radar_melody.
const double kRadarSongMeters = 50;

/// One playable take (version) of a stem.
class StemTake {
  StemTake({required this.label, required this.source, required this.origin, required this.length});
  final String label;
  final AudioSource source;
  final TakeOrigin origin;
  final Duration length;
}

/// Situational Suno song player: exactly one song plays at a time, picked
/// from what you're doing (see [_chooseSong]), with ~1.5 s crossfades.
///
/// * Songs that aren't playing are paused, so each resumes where you left it.
/// * radar_melody runs through a low-pass biquad + pan driven by the compass;
///   excavate_hype through a resonant low-pass boosted by each shake.
/// * A song with two takes (`name.mp3` + `name1.mp3`) alternates between them.
/// * Any song missing from `Song/` falls back to a synthesized 114 BPM loop.
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
  Timer? _tick;
  final Map<Stem, int> _takeIndex = {for (final s in Stem.values) s: 0};
  final Map<Stem, bool> _paused = {};
  final Map<Stem, double> _level = {for (final s in Stem.values) s: 0};
  bool _metroPaused = true;

  /// The one song (or the metronome) currently playing.
  MusicState state = MusicState.metronome;
  static const Duration _walkHold = Duration(milliseconds: 1600);
  static const Duration _shakeHold = Duration(seconds: 4);
  static const Duration _idleAfter = Duration(seconds: 10);
  DateTime _lastStepAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastShakeAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _stillSince;
  bool _nearRelic = false;

  // Live inputs.
  double _stepBpm = 0;
  RadarReading? _reading;
  GamePhase _phase = GamePhase.locating;
  double _excavationProgress = 0;
  double _resonanceBoost = 0;

  /// Target gains per stem (only one is non-zero at a time).
  final Map<Stem, double> gains = {for (final s in Stem.values) s: 0};

  /// Smoothed, actually-playing level per stem for the drawer's meters.
  double levelOf(Stem s) => _level[s]!;
  double playbackRate = 1;
  double radarCutoff = 250;

  /// Metronome: audible while standing still, gone once you walk.
  AudioSource? _metroSource;
  SoundHandle? _metroVoice;
  double metronomeGain = 0;
  double _metroTarget = 0;

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
      _metroSource = await _soloud.loadMem('metronome_${stemBpm.round()}.wav', renderMetronomeBar());
      ready = true;
      _startAll();
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
    return list[_takeIndex[s]! % list.length];
  }

  /// Starts every song paused (only the active one becomes audible) plus the
  /// metronome loop.
  void _startAll() {
    for (final h in [..._voices.values, ?_metroVoice]) {
      _fadeOutAndStop(h, const Duration(milliseconds: 600));
    }
    _voices.clear();
    _paused.clear();
    for (final s in Stem.values) {
      _takeIndex[s] = 0;
      _launch(s, fadeIn: Duration.zero);
    }
    final metroSrc = _metroSource;
    if (metroSrc != null) {
      final h = _soloud.play(metroSrc, volume: 0, paused: true, looping: true);
      _soloud.setProtectVoice(h, true);
      _metroVoice = h;
      _metroPaused = true;
    }
    _updateStatus();
  }

  /// Creates a (paused) voice for the stem's current take. A stem with two
  /// takes plays each once and then crossfades to the other; a single take loops.
  void _launch(Stem s, {required Duration fadeIn}) {
    final take = currentTake(s);
    if (s.filtered && _filterActivated.add(take.source.soundHash.hash)) {
      // Per-source filters must be activated before the voice is created.
      take.source.filters.biquadFilter.activate();
    }
    final audible = _level[s]! > 0.001;
    final h = _soloud.play(
      take.source,
      volume: 0,
      paused: !audible,
      looping: takes[s]!.length == 1,
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
    _paused[s] = !audible;
    if (audible) _soloud.fadeVolume(h, _volumeFor(s), fadeIn);
  }

  void _fadeOutAndStop(SoundHandle h, Duration d) {
    if (!_soloud.getIsValidVoiceHandle(h)) return;
    _soloud.setPause(h, false);
    _soloud.fadeVolume(h, 0, d);
    _soloud.scheduleStop(h, d);
  }

  double _volumeFor(Stem s) => muted ? 0 : _level[s]!;

  void _onTick() {
    if (!ready || _voices.isEmpty) return;
    _resonanceBoost *= 0.82; // shake resonance decays back down
    _chooseSong();

    // Smooth crossfade: each level eases toward its target (~1.5 s).
    for (final s in Stem.values) {
      _level[s] = _ease(_level[s]!, gains[s]!);
    }
    metronomeGain = _ease(metronomeGain, _metroTarget);

    for (final s in Stem.values) {
      var h = _voices[s]!;
      final take = currentTake(s);

      // Alternate takes when the current one is about to end (only matters
      // while it's playing; a paused song resumes where you left it).
      if (takes[s]!.length > 1 && _paused[s] == false) {
        final ending = !_soloud.getIsValidVoiceHandle(h) ||
            _soloud.getPosition(h) >= take.length - _xfade * playbackRate;
        if (ending) {
          _fadeOutAndStop(h, _xfade);
          _takeIndex[s] = _takeIndex[s]! + 1;
          _launch(s, fadeIn: _xfade);
          h = _voices[s]!;
          _updateStatus();
          continue;
        }
      }
      if (!_soloud.getIsValidVoiceHandle(h)) continue;

      final audible = _level[s]! > 0.001;
      if (audible && _paused[s] == true) {
        _soloud.setPause(h, false);
        _paused[s] = false;
      } else if (!audible && _paused[s] == false) {
        // Fully faded out: pause so it picks up where it left off next time.
        _soloud.setPause(h, true);
        _paused[s] = true;
      }
      if (!audible) continue;

      _soloud.fadeVolume(h, _volumeFor(s), _ramp);
      _soloud.fadeRelativePlaySpeed(h, playbackRate, _ramp);
      if (s == Stem.radarMelody) {
        final f = currentTake(s).source.filters.biquadFilter;
        f.frequency(soundHandle: h).fadeFilterParameter(to: radarCutoff, time: _ramp);
        _soloud.setPan(h, _radarPan);
      } else if (s == Stem.excavateHype) {
        final f = currentTake(s).source.filters.biquadFilter;
        f.frequency(soundHandle: h).fadeFilterParameter(to: _excavateCutoff, time: _ramp);
        f.resonance(soundHandle: h).fadeFilterParameter(to: (2 + _resonanceBoost).clamp(0.1, 20), time: _ramp);
      }
    }

    final metro = _metroVoice;
    if (metro != null && _soloud.getIsValidVoiceHandle(metro)) {
      final audible = metronomeGain > 0.001;
      if (audible == _metroPaused) {
        _soloud.setPause(metro, !audible);
        _metroPaused = !audible;
      }
      if (audible) _soloud.fadeVolume(metro, _metroVolume, _ramp);
    }
    notifyListeners();
  }

  static double _ease(double from, double to) {
    final next = from + (to - from) * 0.2;
    return (next - to).abs() < 0.002 ? to : next;
  }

  void _updateStatus() {
    status = 'Now: ${activeLabel.toLowerCase()}';
  }

  // ------------------------------------------------------------ situations

  /// One song at a time:
  /// * shaking inside the 15 m zone -> excavate_hype
  /// * walking within 50 m of the relic -> radar_melody (brighter/louder when facing it)
  /// * walking -> walk_groove (from the very first footsteps)
  /// * stopped -> metronome, then idle_ambient after 10 s
  void _chooseSong() {
    final now = DateTime.now();
    final r = _reading;
    final walking = now.difference(_lastStepAt) < _walkHold;
    final shaking = _phase == GamePhase.excavating && now.difference(_lastShakeAt) < _shakeHold;
    if (walking) _stillSince = null;
    _stillSince ??= walking ? null : now;

    // Radar range with hysteresis so GPS jitter at ~50 m doesn't flip songs.
    if (r != null) {
      if (r.distance <= kRadarSongMeters) _nearRelic = true;
      if (r.distance > kRadarSongMeters + 10) _nearRelic = false;
    } else {
      _nearRelic = false;
    }

    final MusicState next;
    if (shaking) {
      next = MusicState.excavate;
    } else if (walking) {
      next = _nearRelic ? MusicState.radar : MusicState.walk;
    } else if (_stillSince != null && now.difference(_stillSince!) >= _idleAfter) {
      next = MusicState.idle;
    } else {
      next = MusicState.metronome;
    }
    if (next != state) {
      state = next;
      _updateStatus();
    }

    for (final s in Stem.values) {
      gains[s] = 0;
    }
    _metroTarget = 0;
    switch (state) {
      case MusicState.metronome:
        _metroTarget = 1;
      case MusicState.idle:
        gains[Stem.idleAmbient] = 1;
      case MusicState.walk:
        gains[Stem.walkGroove] = 1;
      case MusicState.radar:
        // Fades in as you turn toward the relic.
        gains[Stem.radarMelody] = 0.35 + 0.65 * (r?.brightness ?? 0);
      case MusicState.excavate:
        gains[Stem.excavateHype] = 1;
    }

    // Cutoff 250 Hz (facing away) -> 8 kHz (within ±15°), exponential so the
    // sweep sounds even to the ear.
    radarCutoff = r == null ? 250 : 250 * math.pow(8000 / 250, r.brightness).toDouble();
    // Songs follow your cadence within ±8% so they don't sound warped.
    playbackRate = walking && _stepBpm >= 60 ? (_stepBpm / stemBpm).clamp(0.92, 1.08) : 1.0;
  }

  String get activeLabel => switch (state) {
        MusicState.metronome => 'Metronome',
        MusicState.idle => Stem.idleAmbient.label,
        MusicState.walk => Stem.walkGroove.label,
        MusicState.radar => Stem.radarMelody.label,
        MusicState.excavate => Stem.excavateHype.label,
      };

  void update({
    required double stepBpm,
    required DateTime lastStepAt,
    required RadarReading? reading,
    required GamePhase phase,
    required double excavationProgress,
  }) {
    _stepBpm = stepBpm;
    _lastStepAt = lastStepAt;
    _reading = reading;
    _phase = phase;
    _excavationProgress = excavationProgress;
  }

  /// Each shake starts/keeps the dig music and kicks the filter resonance up.
  void onShake() {
    _lastShakeAt = DateTime.now();
    _resonanceBoost = math.min(_resonanceBoost + 5, 17);
  }

  double get _metroVolume => muted ? 0 : metronomeGain * 0.7;

  double get _excavateCutoff => 700 + 7300 * _excavationProgress;

  double get _radarPan {
    final r = _reading;
    if (r == null) return 0;
    return (r.angleDelta / 90).clamp(-1.0, 1.0) * 0.8;
  }

  // ------------------------------------------------------------ audition

  /// Replaces [stem]'s takes with a local MP3 picked by the user.
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
      _replace(stem);
    } catch (e) {
      status = 'Could not load $name: $e';
      notifyListeners();
    }
  }

  void _replace(Stem stem) {
    final old = _voices[stem];
    if (old != null) _fadeOutAndStop(old, const Duration(milliseconds: 600));
    _takeIndex[stem] = 0;
    _launch(stem, fadeIn: const Duration(milliseconds: 600));
    notifyListeners();
  }

  /// Drops picked files and goes back to the bundled stems / synth fallback.
  void restoreDefaults() {
    if (!ready) return;
    for (final s in Stem.values) {
      takes[s] = List.of(_defaults[s]!);
      _replace(s);
    }
  }

  void setMuted(bool m) {
    muted = m;
    if (ready) {
      for (final s in Stem.values) {
        final h = _voices[s];
        if (h != null && _soloud.getIsValidVoiceHandle(h)) _soloud.fadeVolume(h, _volumeFor(s), _ramp);
      }
      final metro = _metroVoice;
      if (metro != null && _soloud.getIsValidVoiceHandle(metro)) _soloud.fadeVolume(metro, _metroVolume, _ramp);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
