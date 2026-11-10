import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_controller.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final game = GameController();
  runApp(SonicSeekerApp(game: game));
  // Start sensors/audio after the first frame so permission dialogs have a UI behind them.
  WidgetsBinding.instance.addPostFrameCallback((_) => game.init());
}

class SonicSeekerApp extends StatelessWidget {
  const SonicSeekerApp({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sonic Seeker',
      debugShowCheckedModeBanner: false,
      theme: buildSonicTheme(),
      home: HomeScreen(game: game),
    );
  }
}
