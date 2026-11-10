import 'package:flutter/material.dart';

import '../config.dart';
import '../game/game_controller.dart';
import '../models/radar_reading.dart';
import 'theme.dart';

/// Bottom sheet with game actions, inventory and the Desk Simulator controls.
class DebugDrawer extends StatelessWidget {
  const DebugDrawer({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.12,
      minChildSize: 0.12,
      maxChildSize: 0.55,
      snap: true,
      builder: (context, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B1220),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: SonicColors.panelBorder)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: SonicColors.textDim, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: game.userPosition == null ? null : game.respawnRelics,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Respawn Nearby Relics'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SimChip(game: game),
                ],
              ),
              const SizedBox(height: 14),
              _Inventory(game: game),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: game.simulatorMode,
                onChanged: game.setSimulatorMode,
                title: const Text('Desk Simulator Mode'),
                subtitle: Text(
                  game.gpsAvailable ? 'Override GPS, compass & cadence' : 'No GPS detected — simulator active',
                  style: const TextStyle(fontSize: 12, color: SonicColors.textDim),
                ),
              ),
              if (game.simulatorMode) _SimulatorControls(game: game),
            ],
          ),
        );
      },
    );
  }
}

class _SimChip extends StatelessWidget {
  const _SimChip({required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: panelDecoration(glow: game.simulatorMode ? SonicColors.magenta : null),
      child: Text(
        game.simulatorMode ? 'SIM' : 'LIVE',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: game.simulatorMode ? SonicColors.magenta : SonicColors.cyan,
        ),
      ),
    );
  }
}

class _Inventory extends StatelessWidget {
  const _Inventory({required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INVENTORY (${game.inventory.length})',
          style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: SonicColors.textDim),
        ),
        const SizedBox(height: 6),
        if (game.inventory.isEmpty)
          const Text('No relics yet. Follow the brightest tone.', style: TextStyle(color: SonicColors.textDim))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in game.inventory)
                Chip(
                  avatar: Icon(Icons.music_note, size: 16, color: r.rarity.color),
                  label: Text('${r.name} (${r.note.name})', style: const TextStyle(fontSize: 12)),
                  side: BorderSide(color: r.rarity.color.withValues(alpha: 0.6)),
                  backgroundColor: SonicColors.background,
                ),
            ],
          ),
      ],
    );
  }
}

class _SimulatorControls extends StatelessWidget {
  const _SimulatorControls({required this.game});
  final GameController game;

  @override
  Widget build(BuildContext context) {
    const s = kSimDpadStepMeters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Virtual D-pad
            SizedBox(
              width: 156,
              height: 156,
              child: Stack(
                children: [
                  _dpad(Alignment.topCenter, Icons.keyboard_arrow_up, 'Walk North', () => game.simMove(s, 0)),
                  _dpad(Alignment.bottomCenter, Icons.keyboard_arrow_down, 'Walk South', () => game.simMove(-s, 0)),
                  _dpad(Alignment.centerLeft, Icons.keyboard_arrow_left, 'Walk West', () => game.simMove(0, -s)),
                  _dpad(Alignment.centerRight, Icons.keyboard_arrow_right, 'Walk East', () => game.simMove(0, s)),
                  const Align(
                    child: Text('${kSimDpadStepMeters ~/ 1}m', style: TextStyle(fontSize: 11, color: SonicColors.textDim)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: game.phase == GamePhase.excavating ? game.simulateShake : null,
                    icon: const Icon(Icons.vibration),
                    label: const Text('Simulate Shake'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: game.reading == null ? null : game.simJumpNearTarget,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Jump 20m from relic'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.explore, color: SonicColors.cyan, size: 20),
            const SizedBox(width: 8),
            Text('Heading ${game.heading.round()}°', style: const TextStyle(fontSize: 13)),
          ],
        ),
        Slider(
          value: game.heading.clamp(0, 359.9),
          max: 359.9,
          onChanged: game.setSimHeading,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: game.simWalking,
          onChanged: game.setSimWalking,
          title: Text('Simulate ${kSimWalkBpm.round()} BPM Walking'),
          subtitle: const Text(
            'Feeds steps to the cadence engine and walks you along your heading',
            style: TextStyle(fontSize: 12, color: SonicColors.textDim),
          ),
        ),
      ],
    );
  }

  Widget _dpad(Alignment a, IconData icon, String tooltip, VoidCallback onTap) {
    return Align(
      alignment: a,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        iconSize: 30,
        onPressed: onTap,
        icon: Icon(icon),
      ),
    );
  }
}
