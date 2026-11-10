/// Global tunables for Sonic Seeker.
library;

/// Google Maps is only rendered when this is true. Until an API key has been
/// configured natively (see README), the app falls back to the CustomPainter
/// radar so it runs out of the box.
///
/// Enable with: `flutter run --dart-define=MAPS_ENABLED=true`
const bool kGoogleMapsEnabled = bool.fromEnvironment('MAPS_ENABLED');

/// Fallback start location for Desk Simulator Mode when no GPS fix exists.
const double kDefaultLat = 37.7749;
const double kDefaultLng = -122.4194;

// Gameplay
const int kRelicCount = 5;
const double kSpawnMinMeters = 60;
const double kSpawnMaxMeters = 300;
const double kExcavationRadius = 15;
const double kExcavationExitRadius = 25; // hysteresis so GPS jitter doesn't cancel a dig
const double kShakeProgressPerHit = 0.2;

// Motion
const double kStepThreshold = 1.4; // m/s² (gravity-free user acceleration)
const Duration kStepDebounce = Duration(milliseconds: 300);
const double kShakeThreshold = 18.0; // m/s²
const Duration kShakeDebounce = Duration(milliseconds: 350);

// Audio
const double kIdleBpm = 80;
const double kSimWalkBpm = 115;
const double kAlignedDegrees = 15;

// Haptics (Geiger counter)
const double kGeigerFarMeters = 200;
const double kGeigerNearMeters = 15;
const int kGeigerSlowMs = 2000;
const int kGeigerFastMs = 150;

// Desk simulator
const double kSimDpadStepMeters = 10;
const double kSimStrideMeters = 0.75;
