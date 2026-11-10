import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../game/game_controller.dart';
import '../utils/geo_math.dart';
import 'radar_painter.dart';
import 'theme.dart';
import 'walker.dart';

/// Key-free street map (OpenStreetMap data, CARTO dark tiles) with the
/// animated walker pinned to the player's position at the center.
class StreetMapView extends StatefulWidget {
  const StreetMapView({super.key, required this.game, required this.animation, this.bottomInset = 0});

  final GameController game;
  final Animation<double> animation;

  /// Space covered by the bottom drawer, so the attribution stays visible.
  final double bottomInset;

  @override
  State<StreetMapView> createState() => _StreetMapViewState();
}

class _StreetMapViewState extends State<StreetMapView> {
  final MapController _map = MapController();
  bool _mapReady = false;
  Timer? _recenter;

  static LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

  /// Luminance-invert + contrast + cyan tint. Light land goes near-black,
  /// roads/buildings/water pick out as teal lines and shapes.
  static final ColorFilter _nightFilter = () {
    const contrast = 1.6;
    const offset = -12.0;
    const tint = [0.30, 0.85, 1.0]; // r, g, b
    final rows = <double>[];
    for (final t in tint) {
      final a = contrast * t;
      rows.addAll([-0.30 * a, -0.59 * a, -0.11 * a, 0, 255 * a + offset * t]);
    }
    rows.addAll([0, 0, 0, 1, 0]);
    return ColorFilter.matrix(rows);
  }();

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_follow);
  }

  @override
  void dispose() {
    _recenter?.cancel();
    widget.game.removeListener(_follow);
    _map.dispose();
    super.dispose();
  }

  void _follow() {
    final p = widget.game.userPosition;
    if (!_mapReady || p == null) return;
    final cam = _map.camera;
    if (GeoMath.distance(GeoPoint(cam.center.latitude, cam.center.longitude), p) < 0.3) return;
    _map.move(_ll(p), cam.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final user = game.userPosition;
    if (user == null) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _ll(user),
            initialZoom: 17.5,
            minZoom: 14,
            maxZoom: 19,
            backgroundColor: SonicColors.background,
            // Zoom only: the camera stays locked on the player.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
            ),
            onMapReady: () => _mapReady = true,
            onMapEvent: (e) {
              if (e.source == MapEventSource.mapController) return;
              _recenter?.cancel();
              _recenter = Timer(const Duration(milliseconds: 350), _follow);
            },
          ),
          children: [
            TileLayer(
              // Key-free OpenStreetMap tiles (identify the app per OSM tile policy).
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sonicseeker.sonic_seeker',
              maxNativeZoom: 19,
              // Turn the light OSM style into a dark, cyan-tinted night map.
              tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _nightFilter, child: tile),
            ),
            ListenableBuilder(
              listenable: game,
              builder: (context, _) => CircleLayer(
                circles: [
                  for (var i = 0; i < game.trail.length; i++)
                    CircleMarker(
                      point: _ll(game.trail[i]),
                      radius: 0.9,
                      useRadiusInMeter: true,
                      color: SonicColors.magenta.withValues(alpha: 0.15 + 0.65 * (i + 1) / game.trail.length),
                    ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: widget.animation,
              builder: (context, _) {
                final pulse = (widget.animation.value * 2) % 1.0;
                return CircleLayer(
                  circles: [
                    for (final r in game.relics.where((r) => !r.collected)) ...[
                      CircleMarker(
                        point: _ll(r.position),
                        radius: kExcavationRadius + pulse * 35,
                        useRadiusInMeter: true,
                        color: r.rarity.color.withValues(alpha: (1 - pulse) * 0.12),
                        borderColor: r.rarity.color.withValues(alpha: 1 - pulse),
                        borderStrokeWidth: 2,
                      ),
                      CircleMarker(
                        point: _ll(r.position),
                        radius: kExcavationRadius,
                        useRadiusInMeter: true,
                        color: r.rarity.color.withValues(alpha: 0.1),
                        borderColor: r.rarity.color.withValues(alpha: 0.7),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ],
                );
              },
            ),
            ListenableBuilder(
              listenable: game,
              builder: (context, _) => MarkerLayer(
                markers: [
                  for (final r in game.relics.where((r) => !r.collected))
                    Marker(
                      point: _ll(r.position),
                      width: 120,
                      height: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: r.rarity.color,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: r.rarity.color, blurRadius: 10)],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: r.rarity.color, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: widget.animation,
            builder: (context, _) => CustomPaint(
              painter: RadarSweepPainter(sweep: widget.animation.value, drawRings: true),
            ),
          ),
        ),
        // North-up map: the walker sits at the camera center; cone = compass heading.
        Center(
          child: IgnorePointer(
            child: WalkerAvatar(
              bpm: game.stepBpm,
              coneAngleDeg: game.heading,
              aligned: game.reading?.isAligned ?? false,
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: widget.bottomInset + 6,
          child: const IgnorePointer(
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 9, color: SonicColors.textDim),
            ),
          ),
        ),
      ],
    );
  }
}
