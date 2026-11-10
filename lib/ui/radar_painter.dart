import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/relic.dart';
import '../utils/geo_math.dart';
import 'theme.dart';

/// Rotating radar sweep. Used alone as an overlay on Google Maps.
class RadarSweepPainter extends CustomPainter {
  RadarSweepPainter({required this.sweep, this.drawRings = false});

  /// 0..1 animation phase.
  final double sweep;
  final bool drawRings;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.46;
    final angle = sweep * 2 * math.pi;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi / 2.5,
        colors: [SonicColors.cyan.withValues(alpha: 0.0), SonicColors.cyan.withValues(alpha: 0.28)],
        transform: GradientRotation(angle - math.pi / 2 - math.pi / 2.5),
      ).createShader(rect);
    canvas.drawArc(rect, angle - math.pi / 2 - math.pi / 2.5, math.pi / 2.5, true, paint);
    canvas.drawLine(
      c,
      c + Offset(math.cos(angle - math.pi / 2), math.sin(angle - math.pi / 2)) * r,
      Paint()
        ..color = SonicColors.cyan.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );
    if (drawRings) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..color = SonicColors.cyan.withValues(alpha: 0.15);
      for (var i = 1; i <= 3; i++) {
        canvas.drawCircle(c, r * i / 3, ring);
      }
    }
  }

  @override
  bool shouldRepaint(RadarSweepPainter old) => old.sweep != sweep;
}

/// Full fallback radar (no Google Maps key needed). Heading-up display
/// centered on the player, range = [rangeMeters].
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.user,
    required this.heading,
    required this.relics,
    required this.sweep,
    required this.pulse,
    this.trail = const [],
    this.targetId,
    this.rangeMeters = 350,
  });

  /// Footprint breadcrumbs, oldest first.
  final List<GeoPoint> trail;

  final GeoPoint? user;
  final double heading;
  final List<Relic> relics;
  final double sweep;
  final double pulse;
  final String? targetId;
  final double rangeMeters;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = SonicColors.background);
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.46;
    final pxPerMeter = r / rangeMeters;

    // Background grid
    final grid = Paint()
      ..color = SonicColors.grid.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    const step = 32.0;
    for (var x = c.dx % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = c.dy % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Range rings with labels every 100m
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = SonicColors.cyan.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    final ringStep = const [10, 25, 50, 100].firstWhere((s) => rangeMeters / s <= 4, orElse: () => 100);
    for (var m = ringStep; m <= rangeMeters; m += ringStep) {
      canvas.drawCircle(c, m * pxPerMeter, ring);
      _label(canvas, '${m}m', c + Offset(4, -m * pxPerMeter - 14), SonicColors.cyanDim, 10);
    }
    // Excavation zone
    canvas.drawCircle(
      c,
      kExcavationRadius * pxPerMeter,
      Paint()
        ..color = SonicColors.magenta.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // North indicator (rotates opposite to heading since display is heading-up)
    final northAngle = (-heading) * math.pi / 180 - math.pi / 2;
    final nPos = c + Offset(math.cos(northAngle), math.sin(northAngle)) * (r + 14);
    _label(canvas, 'N', nPos - const Offset(5, 7), SonicColors.magenta, 13, bold: true);

    RadarSweepPainter(sweep: sweep).paint(canvas, size);

    final u = user;
    Offset project(GeoPoint p) {
      final d = GeoMath.distance(u!, p);
      final rel = (GeoMath.bearing(u, p) - heading) * math.pi / 180 - math.pi / 2;
      return c + Offset(math.cos(rel), math.sin(rel)) * d * pxPerMeter;
    }

    // Footprint trail: alternating left/right prints along the path, fading with age.
    if (u != null && trail.length > 1) {
      final pts = [...trail.map(project), c];
      for (var i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final dir = pts[i + 1] - a;
        if (dir.distance < 0.5) continue;
        final ang = math.atan2(dir.dy, dir.dx);
        final side = (i.isEven ? 1 : -1) * 3.0;
        final pos = a + Offset(-math.sin(ang), math.cos(ang)) * side;
        final age = (i + 1) / pts.length; // 0 = oldest
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(ang);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 7, height: 3.6),
          Paint()..color = SonicColors.magenta.withValues(alpha: 0.12 + 0.6 * age),
        );
        canvas.restore();
      }
    }

    // Relics
    if (u != null) {
      for (final relic in relics) {
        final d = GeoMath.distance(u, relic.position);
        final b = GeoMath.bearing(u, relic.position);
        final rel = (b - heading) * math.pi / 180 - math.pi / 2;
        final clampedD = math.min(d, rangeMeters);
        final p = c + Offset(math.cos(rel), math.sin(rel)) * clampedD * pxPerMeter;
        final color = relic.rarity.color;
        if (relic.collected) {
          canvas.drawCircle(p, 4, Paint()..color = color.withValues(alpha: 0.25));
          continue;
        }
        final isTarget = relic.id == targetId;
        // Pulsing halo
        for (var k = 0; k < 2; k++) {
          final ph = (pulse + k * 0.5) % 1.0;
          canvas.drawCircle(
            p,
            6 + ph * (isTarget ? 30 : 20),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = color.withValues(alpha: (1 - ph) * 0.8),
          );
        }
        canvas.drawCircle(p, isTarget ? 7 : 5, Paint()..color = color);
        if (d > rangeMeters) {
          _label(canvas, '${d.round()}m ›', p + const Offset(8, -6), color, 10);
        }
      }
    }

    // The player is drawn by the animated WalkerAvatar overlaid at the center.
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(RadarPainter old) => true;
}
