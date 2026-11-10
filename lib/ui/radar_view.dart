import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import 'radar_painter.dart';
import 'walker.dart';

/// Fallback radar canvas used when Google Maps isn't configured.
/// Auto-zooms toward the nearest relic so footprints stay visible up close.
class RadarView extends StatefulWidget {
  const RadarView({super.key, required this.game, required this.animation});

  final GameController game;
  final Animation<double> animation;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> {
  double _range = 350;

  double get _targetRange {
    final d = widget.game.reading?.distance;
    if (d == null) return 350;
    return (d * 1.5).clamp(40.0, 350.0);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            // Ease the zoom a little each frame.
            _range += (_targetRange - _range) * 0.06;
            final t = widget.animation.value;
            return CustomPaint(
              size: Size.infinite,
              painter: RadarPainter(
                user: game.userPosition,
                heading: game.heading,
                relics: game.relics,
                trail: game.trail,
                sweep: t,
                pulse: (t * 2) % 1.0,
                targetId: game.reading?.target.id,
                rangeMeters: _range,
              ),
            );
          },
        ),
        if (game.userPosition != null)
          Center(
            child: IgnorePointer(
              // Heading-up display: the player always faces up the screen.
              child: WalkerAvatar(
                bpm: game.stepBpm,
                coneAngleDeg: 0,
                aligned: game.reading?.isAligned ?? false,
              ),
            ),
          ),
      ],
    );
  }
}
