# Sonic Seeker

A location-based audio treasure hunt. Your walking cadence drives a synthesized pulse, and GPS plus compass lead you to procedural **Sound Relics**. Get within 15 m and shake the phone to dig one up.

All audio is synthesized in Dart (`lib/services/synth.dart`) and played through `flutter_soloud`, so the app has no audio assets.

## Run

```bash
flutter pub get
flutter run
```

Without a Google Maps key the app shows the built-in CustomPainter radar. If there's no GPS (desk, emulator, permission denied), it switches to **Desk Simulator Mode** on its own.

## Desk Simulator (bottom drawer)
- D-pad: moves you 10 m N/S/E/W
- Heading slider: stands in for the compass
- *Simulate 115 BPM Walking*: feeds steps to the cadence engine and walks you along your heading (stops when you reach a dig site)
- *Simulate Shake*: adds 20% to excavation progress
- *Jump 20m from relic*: teleports you near the nearest relic

## Enabling Google Maps (optional)
1. **Android:** add `MAPS_API_KEY=your_key` to `android/local.properties`.
2. **iOS:** copy `ios/Flutter/MapsKey.xcconfig.example` to `ios/Flutter/MapsKey.xcconfig` and fill in the key. This file is gitignored.
3. Run with `flutter run --dart-define=MAPS_ENABLED=true`. A button lets you switch between map and radar.

## Layout
```
lib/
  config.dart                 tunables (thresholds, radii, BPMs)
  game/game_controller.dart   ChangeNotifier game state machine
  models/                     Relic, rarity, pentatonic notes, RadarReading
  services/
    relic_spawner_service.dart  5 relics, 60–300 m, random bearings
    motion_service.dart         step peak detector (300 ms debounce) + shake (>18 m/s²)
    location_service.dart       geolocator + virtual position
    heading_service.dart        flutter_compass + simulated heading
    audio_radar_service.dart    beat loop, beacon pings, Geiger haptics
    synth.dart                  PCM/WAV synthesizer
  ui/                         HUD, radar painter, map view, drawer, excavation overlay
```
