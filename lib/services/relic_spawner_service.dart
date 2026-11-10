import 'dart:math' as math;

import '../config.dart';
import '../models/relic.dart';
import '../utils/geo_math.dart';

/// Procedurally places Sound Relics around the player.
class RelicSpawnerService {
  RelicSpawnerService({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  int _counter = 0;

  static const _prefixes = ['Echo', 'Resonant', 'Hollow', 'Glass', 'Phase', 'Static', 'Lunar', 'Prism', 'Drift', 'Ghost'];
  static const _nouns = ['Shard', 'Bell', 'Chime', 'Spire', 'Totem', 'Fossil', 'Lattice', 'Orb', 'Reed', 'Cassette'];

  /// Spawns [count] relics at random bearings between [minMeters] and [maxMeters].
  List<Relic> spawnAround(
    GeoPoint origin, {
    int count = kRelicCount,
    double minMeters = kSpawnMinMeters,
    double maxMeters = kSpawnMaxMeters,
  }) {
    // Shuffle the scale so the batch uses distinct notes.
    final notes = List<PentatonicNote>.from(PentatonicNote.scale)..shuffle(_rng);
    return List.generate(count, (i) {
      final bearing = _rng.nextDouble() * 360.0;
      // sqrt keeps the spatial density roughly even across the annulus.
      final u = _rng.nextDouble();
      final dist = math.sqrt(minMeters * minMeters + u * (maxMeters * maxMeters - minMeters * minMeters));
      final rarity = _rollRarity();
      _counter++;
      return Relic(
        id: 'relic_$_counter',
        name: '${_prefixes[_rng.nextInt(_prefixes.length)]} ${_nouns[_rng.nextInt(_nouns.length)]}',
        position: GeoMath.offset(origin, bearing, dist),
        note: notes[i % notes.length],
        rarity: rarity,
      );
    });
  }

  RelicRarity _rollRarity() {
    final total = RelicRarity.values.fold<int>(0, (s, r) => s + r.weight);
    var roll = _rng.nextInt(total);
    for (final r in RelicRarity.values) {
      if (roll < r.weight) return r;
      roll -= r.weight;
    }
    return RelicRarity.common;
  }
}
