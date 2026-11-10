import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

/// Neon side-view walker whose stride is locked to the live step cadence.
///
/// One full walk cycle = two footsteps, so at 115 BPM the legs swing at
/// 0.96 cycles per second, in time with the beat. When idle, the figure stands
/// and breathes.
class WalkerAvatar extends StatefulWidget {
  const WalkerAvatar({
    super.key,
    required this.bpm,
    required this.coneAngleDeg,
    this.size = 112,
    this.aligned = false,
  });

  /// Live step cadence (0 when standing still).
  final double bpm;

  /// Screen angle the heading cone points at (0 = up, clockwise).
  final double coneAngleDeg;
  final double size;

  /// Glow brighter when facing the target relic.
  final bool aligned;

  @override
  State<WalkerAvatar> createState() => _WalkerAvatarState();
}

class _WalkerAvatarState extends State<WalkerAvatar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0; // walk-cycle position, in cycles
  double _stride = 0; // 0 = standing, 1 = full stride (eased)
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final walking = widget.bpm >= 40;
    _stride += ((walking ? 1.0 : 0.0) - _stride) * math.min(1.0, dt * 4);
    final cycleHz = walking ? widget.bpm / 120.0 : 0.6;
    setState(() {
      _phase = (_phase + dt * cycleHz) % 1.0;
      _time += dt;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: WalkerPainter(
          phase: _phase,
          stride: _stride,
          time: _time,
          coneAngle: widget.coneAngleDeg * math.pi / 180,
          aligned: widget.aligned,
        ),
      ),
    );
  }
}

class WalkerPainter extends CustomPainter {
  WalkerPainter({
    required this.phase,
    required this.stride,
    required this.time,
    required this.coneAngle,
    required this.aligned,
  });

  final double phase;
  final double stride;
  final double time;
  final double coneAngle;
  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final accent = aligned ? SonicColors.cyan : SonicColors.cyan.withValues(alpha: 0.7);

    // Heading cone
    const spread = 0.55;
    final coneRect = Rect.fromCircle(center: c, radius: r);
    final start = coneAngle - math.pi / 2 - spread / 2;
    canvas.drawArc(
      coneRect,
      start,
      spread,
      true,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: aligned ? 0.65 : 0.4), accent.withValues(alpha: 0)],
        ).createShader(coneRect),
    );

    // Base disc
    final discR = r * 0.5;
    canvas.drawCircle(c, discR, Paint()..color = SonicColors.background.withValues(alpha: 0.85));
    canvas.drawCircle(
      c,
      discR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );

    // Figure (side view, facing right), scaled to fit the disc.
    final h = discR * 1.55;
    final tau = 2 * math.pi;
    final swing = 0.55 * stride;
    final breathe = (1 - stride) * math.sin(time * 2.4) * 0.012 * h;
    final bob = -stride * (math.sin(phase * tau * 2).abs()) * 0.035 * h + breathe;
    final hip = c + Offset(0, h * 0.08 + bob);
    final lean = 0.12 * stride;
    final shoulder = hip + Offset(math.sin(lean) * h * 0.3, -math.cos(lean) * h * 0.3);
    final head = shoulder + Offset(math.sin(lean) * h * 0.13, -h * 0.13);

    Offset limb(Offset from, double angle, double len) =>
        from + Offset(math.sin(angle) * len, math.cos(angle) * len);

    final legs = <List<Offset>>[];
    final arms = <List<Offset>>[];
    for (final offset in const [0.0, 0.5]) {
      final p = (phase + offset) % 1.0;
      final thigh = swing * math.sin(p * tau);
      // Knee flexes mostly during the swing phase (leg moving forward).
      final knee = stride * (0.15 + 0.75 * math.max(0, math.sin(p * tau + math.pi / 2)));
      final kneePos = limb(hip, thigh, h * 0.24);
      final foot = limb(kneePos, thigh - knee, h * 0.24);
      legs.add([hip, kneePos, foot]);

      final upper = -swing * 0.8 * math.sin(p * tau);
      final elbow = limb(shoulder, upper, h * 0.17);
      final hand = limb(elbow, upper + 0.25 + 0.6 * stride, h * 0.15);
      arms.add([shoulder, elbow, hand]);
    }

    void stroke(List<List<Offset>> chains, Color color, double width, {double blur = 0}) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      for (final chain in chains) {
        final path = Path()..moveTo(chain.first.dx, chain.first.dy);
        for (final pt in chain.skip(1)) {
          path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    final w = h * 0.075;
    // Back limbs dimmer for depth.
    final back = [legs[1], arms[1]];
    final front = [legs[0], arms[0], [hip, shoulder]];
    stroke(back, accent.withValues(alpha: 0.35), w);
    stroke(front, accent, w * 2.2, blur: 3); // glow
    stroke(front, SonicColors.text, w);
    canvas.drawCircle(head, h * 0.085, Paint()
      ..color = accent
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(head, h * 0.07, Paint()..color = SonicColors.text);
  }

  @override
  bool shouldRepaint(WalkerPainter old) =>
      old.phase != phase || old.time != time || old.stride != stride || old.coneAngle != coneAngle || old.aligned != aligned;
}
