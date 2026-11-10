import 'dart:ui' show Color;

import '../utils/geo_math.dart';

enum RelicRarity {
  common('Common', Color(0xFF7DF9FF), 55),
  rare('Rare', Color(0xFF4D8BFF), 25),
  epic('Epic', Color(0xFFC86BFF), 15),
  legendary('Legendary', Color(0xFFFFC94D), 5);

  const RelicRarity(this.label, this.color, this.weight);
  final String label;
  final Color color;
  final int weight;

  /// Harmonic intervals stacked on the root note. Rarer relics sing richer chords.
  List<double> get chordRatios => switch (this) {
        RelicRarity.common => const [1.0],
        RelicRarity.rare => const [1.0, 1.5],
        RelicRarity.epic => const [1.0, 1.5, 2.0],
        RelicRarity.legendary => const [1.0, 1.26, 1.5, 2.0],
      };
}

/// A single note of the C-major pentatonic scale.
class PentatonicNote {
  const PentatonicNote(this.name, this.frequency);
  final String name;
  final double frequency;

  static const List<PentatonicNote> scale = [
    PentatonicNote('C4', 261.63),
    PentatonicNote('D4', 293.66),
    PentatonicNote('E4', 329.63),
    PentatonicNote('G4', 392.00),
    PentatonicNote('A4', 440.00),
    PentatonicNote('C5', 523.25),
    PentatonicNote('D5', 587.33),
    PentatonicNote('E5', 659.25),
    PentatonicNote('G5', 783.99),
    PentatonicNote('A5', 880.00),
  ];
}

class Relic {
  Relic({
    required this.id,
    required this.name,
    required this.position,
    required this.note,
    required this.rarity,
  });

  final String id;
  final String name;
  final GeoPoint position;
  final PentatonicNote note;
  final RelicRarity rarity;
  bool collected = false;
  DateTime? collectedAt;

  /// All chord frequencies for this relic.
  List<double> get chord => [for (final r in rarity.chordRatios) note.frequency * r];

  /// Stable key for audio caches.
  String get soundKey => '${note.name}_${rarity.name}';
}
