# Sonic Seeker

A location-based audio treasure hunt. Your walking cadence drives a synthesized pulse, and GPS plus compass lead you to procedural **Sound Relics**. Get within 15 m and shake the phone to dig one up.

## Music: Suno stems + live mix
Put stems in `Song/` as `<name>.mp3`, with an optional second take `<name>1.mp3` (any number works):
`idle_ambient`, `walk_groove`, `radar_melody`, `excavate_hype`. Any stem that's missing falls back to a synthesized 114 BPM loop (`lib/services/stem_synth.dart`).

`StemEngine` plays **one song at a time**, picked from what you're doing, with ~1.5 s crossfades:

| Situation | Song |
|---|---|
| Stopped (crosswalk, pause) | 114 BPM metronome, then `idle_ambient` after 10 s |
| Footsteps detected | `walk_groove` (starts on your first steps, tempo follows cadence ±8%) |
| Walking within 50 m of a relic | `radar_melody`: fades in and opens its low-pass (250 Hz → 8 kHz) as you face the relic, panned toward it |
| Shaking inside the 15 m dig zone | `excavate_hype`: each shake boosts the filter resonance; the cutoff opens as the dig progresses |

Songs that aren't playing are paused, so each one picks up where you left it. A song with two takes alternates between them each time it ends. The drawer's **Music** panel shows which song is playing and has a picker to audition any local MP3 for any slot.

The beacon pings, excavation stabs and unlock arpeggio are still synthesized in `lib/services/synth.dart`.

## Map
By default the app shows key-free OpenStreetMap tiles, tinted dark in code, with the animated walker locked to your position. The button above the drawer switches to the radar view.

## Run

```bash
flutter pub get
flutter run
```

Without a Google Maps key the app uses OpenStreetMap tiles. If there's no GPS (desk, emulator, permission denied), it switches to **Desk Simulator Mode** on its own.

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
