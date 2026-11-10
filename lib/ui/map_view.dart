import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config.dart';
import '../game/game_controller.dart';
import '../models/relic.dart';
import '../utils/geo_math.dart';
import 'map_style.dart';
import 'radar_painter.dart';
import 'theme.dart';
import 'walker.dart';

/// Dark-mode Google Map with pulsing relic circles and a radar sweep overlay.
class SonicMapView extends StatefulWidget {
  const SonicMapView({super.key, required this.game, required this.animation});

  final GameController game;
  final Animation<double> animation;

  @override
  State<SonicMapView> createState() => _SonicMapViewState();
}

class _SonicMapViewState extends State<SonicMapView> {
  GoogleMapController? _controller;
  GeoPoint? _lastCameraTarget;
  GeoPoint? _cameraCenter;
  Timer? _pulseTimer;
  double _pulse = 0;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_followUser);
    // Native circle updates are relatively expensive, so pulse at ~8 fps.
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) setState(() => _pulse = (_pulse + 0.08) % 1.0);
    });
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    widget.game.removeListener(_followUser);
    _controller?.dispose();
    super.dispose();
  }

  void _followUser() {
    final p = widget.game.userPosition;
    final c = _controller;
    if (p == null || c == null) return;
    final last = _lastCameraTarget;
    if (last != null && GeoMath.distance(last, p) < 1) return;
    _lastCameraTarget = p;
    c.animateCamera(CameraUpdate.newLatLng(LatLng(p.lat, p.lng)));
  }

  static double _hueFor(RelicRarity r) => switch (r) {
        RelicRarity.common => BitmapDescriptor.hueCyan,
        RelicRarity.rare => BitmapDescriptor.hueBlue,
        RelicRarity.epic => BitmapDescriptor.hueViolet,
        RelicRarity.legendary => BitmapDescriptor.hueOrange,
      };

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final user = game.userPosition;
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final pulse = _pulse;
        final markers = <Marker>{
          for (final r in game.relics.where((r) => !r.collected))
            Marker(
              markerId: MarkerId(r.id),
              position: LatLng(r.position.lat, r.position.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(r.rarity)),
              infoWindow: InfoWindow(title: r.name, snippet: '${r.rarity.label} · ${r.note.name}'),
            ),
        };
        final trail = game.trail;
        final circles = <Circle>{
          // Footprint breadcrumbs, fading with age.
          for (var i = 0; i < trail.length; i++)
            Circle(
              circleId: CircleId('trail_$i'),
              center: LatLng(trail[i].lat, trail[i].lng),
              radius: 0.8,
              strokeWidth: 0,
              fillColor: SonicColors.magenta.withValues(alpha: 0.15 + 0.6 * (i + 1) / trail.length),
              zIndex: 1,
            ),
          for (final r in game.relics.where((r) => !r.collected)) ...[
            Circle(
              circleId: CircleId('${r.id}_pulse'),
              center: LatLng(r.position.lat, r.position.lng),
              radius: kExcavationRadius + pulse * 35,
              strokeWidth: 2,
              strokeColor: r.rarity.color.withValues(alpha: 1 - pulse),
              fillColor: r.rarity.color.withValues(alpha: (1 - pulse) * 0.12),
            ),
            Circle(
              circleId: CircleId('${r.id}_zone'),
              center: LatLng(r.position.lat, r.position.lng),
              radius: kExcavationRadius,
              strokeWidth: 1,
              strokeColor: r.rarity.color.withValues(alpha: 0.6),
              fillColor: r.rarity.color.withValues(alpha: 0.08),
            ),
          ],
        };
        return Stack(
          fit: StackFit.expand,
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: LatLng(user.lat, user.lng), zoom: 17),
              style: kSonicMapStyle,
              markers: markers,
              circles: circles,
              compassEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              // The camera is locked to the player so the walker overlay stays on them.
              scrollGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              onCameraMove: (pos) => _cameraCenter = GeoPoint(pos.target.latitude, pos.target.longitude),
              onCameraIdle: () {
                // Pinch-zoom can drift the center; snap back onto the player if so.
                final p = game.userPosition;
                final cc = _cameraCenter;
                if (p != null && cc != null && GeoMath.distance(p, cc) > 1) {
                  _lastCameraTarget = null;
                  _followUser();
                }
              },
              onMapCreated: (c) => _controller = c,
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: widget.animation,
                builder: (context, _) => CustomPaint(
                  painter: RadarSweepPainter(sweep: widget.animation.value, drawRings: true),
                ),
              ),
            ),
            // North-up map: the walker sits at the camera center, cone = compass heading.
            Center(
              child: IgnorePointer(
                child: WalkerAvatar(
                  bpm: game.stepBpm,
                  coneAngleDeg: game.heading,
                  aligned: game.reading?.isAligned ?? false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
