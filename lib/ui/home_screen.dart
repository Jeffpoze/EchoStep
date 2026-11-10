import 'package:flutter/material.dart';

import '../config.dart';
import '../game/game_controller.dart';
import 'debug_drawer.dart';
import 'excavation_overlay.dart';
import 'hud.dart';
import 'map_view.dart';
import 'radar_view.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.game});

  final GameController game;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  /// Players can flip between the map and the radar canvas when Maps is enabled.
  bool _showMap = kGoogleMapsEnabled;

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Center: map or fallback radar. Rebuilds only on structural changes.
          ListenableBuilder(
            listenable: game,
            builder: (context, _) => _showMap && game.userPosition != null
                ? SonicMapView(game: game, animation: _sweep)
                : RadarView(game: game, animation: _sweep),
          ),
          ListenableBuilder(
            listenable: game,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                if (game.userPosition == null)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Acquiring signal…', style: TextStyle(color: SonicColors.textDim)),
                      ],
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(alignment: Alignment.topCenter, child: TopHud(game: game)),
                  ),
                ),
                if (kGoogleMapsEnabled)
                  Positioned(
                    right: 12,
                    bottom: MediaQuery.sizeOf(context).height * 0.12 + 12,
                    child: FloatingActionButton.small(
                      heroTag: 'view',
                      tooltip: _showMap ? 'Radar view' : 'Map view',
                      onPressed: () => setState(() => _showMap = !_showMap),
                      child: Icon(_showMap ? Icons.radar : Icons.map),
                    ),
                  ),
                DebugDrawer(game: game),
                // Above the drawer, tucked under the HUD so it never hides the sim controls.
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 150),
                    child: Align(alignment: Alignment.topCenter, child: ExcavationOverlay(game: game)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
