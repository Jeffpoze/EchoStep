# Sonic Seeker

A location-based audio treasure hunt. Your walking cadence drives a synthesized pulse, and GPS plus compass lead you to procedural **Sound Relics**. Get within 15 m and shake the phone to dig one up.

## Music: Suno stems + live mix
Put stems in `Song/` as `<name>.mp3`, with an optional second take `<name>1.mp3` (any number works):
`idle_ambient`, `walk_groove`, `radar_melody`, `excavate_hype`. Any stem that's missing falls back to a synthesized 114 BPM loop (`lib/services/stem_synth.dart`).

`StemEngine` starts all four stems in the same audio frame (one SoLoud voice group), then mixes them live:

| Stem | Rule |
|---|---|
| idle_ambient | 100% when step BPM < 60, ducks to 30% when walking |
| walk_groove | 0% → 100% as BPM rises from 60 → 114 |
| radar_melody | gain by distance 300 m → 15 m; low-pass 250 Hz (facing away) → 8 kHz (within ±15°); pans toward the relic |
| excavate_hype | fades in inside the 15 m zone; each shake boosts filter resonance; the cutoff opens as the dig progresses |

Playback rate tracks cadence (0.92–1.08). The same rate is applied to all stems so they stay locked to each other. When a stem has two takes, the whole mix crossfades to the other take at the end of each loop. The drawer's **Music Stems** panel shows live levels and has a picker so you can audition any local MP3 for any stem.

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
