import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../models/radar_reading.dart';
import 'theme.dart';

/// Center card shown while EXCAVATING, plus the unlock celebration banner.
class ExcavationOverlay extends StatelessWidget {
  const ExcavationOverlay({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final unlocked = game.lastUnlocked;
    if (unlocked != null) {
      return _card(
        glow: unlocked.rarity.color,
        children: [
          Icon(Icons.auto_awesome, color: unlocked.rarity.color, size: 40),
          const SizedBox(height: 8),
          const Text('RELIC UNEARTHED', style: TextStyle(letterSpacing: 2, fontSize: 12, color: SonicColors.textDim)),
          const SizedBox(height: 4),
          Text(unlocked.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text('${unlocked.rarity.label} · ${unlocked.note.name}', style: TextStyle(color: unlocked.rarity.color)),
        ],
      );
    }
    if (game.phase == GamePhase.allCollected) {
      return _card(
        glow: SonicColors.cyan,
        children: [
          const Text('ALL RELICS RECOVERED', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: game.respawnRelics,
            icon: const Icon(Icons.refresh),
            label: const Text('Respawn Nearby Relics'),
          ),
        ],
      );
    }
    final target = game.excavationTarget;
    if (game.phase != GamePhase.excavating || target == null) return const SizedBox.shrink();
    final progress = game.excavationProgress;
    return _card(
      glow: target.rarity.color,
      children: [
        const Text('EXCAVATION ZONE', style: TextStyle(letterSpacing: 2, fontSize: 12, color: SonicColors.magenta)),
        const SizedBox(height: 6),
        Text(target.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(end: progress),
          duration: const Duration(milliseconds: 200),
          builder: (context, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 16,
              backgroundColor: SonicColors.grid,
              valueColor: AlwaysStoppedAnimation(target.rarity.color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vibration, color: SonicColors.cyan),
            SizedBox(width: 8),
            Text('SHAKE TO EXCAVATE', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700, color: SonicColors.cyan)),
          ],
        ),
      ],
    );
  }

  Widget _card({required Color glow, required List<Widget> children}) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(14),
        decoration: panelDecoration(glow: glow),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
