import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../models/radar_reading.dart';
import 'theme.dart';

/// Top heads-up display: cadence, distance, alignment chevron, mute toggle.
class TopHud extends StatelessWidget {
  const TopHud({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final reading = game.reading;
    final aligned = reading?.isAligned ?? false;
    final bpm = game.stepBpm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: panelDecoration(glow: aligned ? SonicColors.cyan : null),
          child: Row(
            children: [
              _Stat(
                label: 'STEP BPM',
                value: bpm > 0 ? bpm.round().toString() : '--',
                sub: 'pulse ${game.tempoBpm.round()}',
              ),
              const _Divider(),
              _Stat(
                label: 'RELIC',
                value: reading == null ? '--' : _fmtDistance(reading.distance),
                sub: reading?.target.rarity.label ?? 'none',
                color: reading?.target.rarity.color,
              ),
              const _Divider(),
              Expanded(child: _AlignmentChevron(reading: reading)),
              IconButton(
                onPressed: game.toggleMute,
                tooltip: game.muted ? 'Unmute' : 'Mute',
                icon: Icon(
                  game.muted ? Icons.volume_off_rounded : Icons.graphic_eq_rounded,
                  color: game.muted ? SonicColors.textDim : SonicColors.cyan,
                ),
              ),
            ],
          ),
        ),
        if (reading != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: panelDecoration(),
              child: Text(
                '${reading.target.name} · ${reading.target.note.name} · '
                '${game.inventory.length}/${game.relics.length} recovered',
                style: const TextStyle(fontSize: 12, color: SonicColors.textDim),
              ),
            ),
          ),
        ],
        if (game.statusMessage != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: panelDecoration(glow: SonicColors.magenta),
            child: Text(game.statusMessage!, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }

  static String _fmtDistance(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}km' : '${m.round()}m';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub, this.color});
  final String label;
  final String value;
  final String sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, letterSpacing: 1.2, color: SonicColors.textDim)),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? SonicColors.text,
          ),
        ),
        Text(sub, style: const TextStyle(fontSize: 10, color: SonicColors.textDim)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 12), color: SonicColors.grid);
}

/// Chevron that rotates toward the relic relative to where the phone faces,
/// glowing cyan when within ±15°.
class _AlignmentChevron extends StatelessWidget {
  const _AlignmentChevron({required this.reading});
  final RadarReading? reading;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final aligned = r?.isAligned ?? false;
    final color = r == null ? SonicColors.textDim : (aligned ? SonicColors.cyan : SonicColors.text.withValues(alpha: 0.6));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedRotation(
          turns: (r?.angleDelta ?? 0) / 360,
          duration: const Duration(milliseconds: 250),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                if (aligned) BoxShadow(color: SonicColors.cyan.withValues(alpha: 0.7), blurRadius: 18, spreadRadius: 2),
              ],
            ),
            child: Icon(Icons.navigation_rounded, size: 32, color: color),
          ),
        ),
        Text(
          r == null ? '' : (aligned ? 'LOCKED' : '${r.angleDelta.round()}°'),
          style: TextStyle(fontSize: 10, letterSpacing: 1, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
