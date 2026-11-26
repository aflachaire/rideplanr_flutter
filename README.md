# RidePlanr — Flutter

Flutter port of the iOS `DriverIntelPrototype` (RidePlanr) app: a driver
positioning-intelligence prototype with live flight, train, event, and
lifestyle demand signals, a Pro paywall, reminders, and a live map.

## Feature parity with the iOS app

- **Onboarding flow** — 3-page carousel with hero card, highlights grid, skip/continue.
- **Home** — greeting, 12-hour Trend chart with busiest window, "Your next moves"
  carousel (ranked live spots with mock-signal fallback), Pro trial promo card,
  12-hour weather forecast (Open-Meteo).
- **Spots** — filterable (All/Flights/Trains/Events/Lifestyle), sortable
  (Soonest/Best score/Nearest) live feed with skeleton loaders, per-feed status
  messages, reminder buttons, and the Pro lock (blur + trial banner).
- **Map** — OpenStreetMap map with balanced spot markers (icon + time + stars),
  category/quality filters, selected-spot card, Pro lock.
- **Account** — settings (distance unit, time format, theme), subscription page
  (plans, benefits, RevenueCat readiness, restore/customer center/manage),
  terms of service and privacy policy.
- **Reminders** — local notifications scheduled `leadTime` minutes before a
  saved spot starts; tapping a reminder deep-links to the spot in Spots.
- **RevenueCat** — `purchases_flutter` + `purchases_ui_flutter`; remote paywall
  when configured, local fallback paywall + trial otherwise; entitlement-based
  free/trial/pro tiers persisted across launches.

## APIs (same providers as iOS)

| Source | Provider |
|---|---|
| Weather | Open-Meteo |
| Airports | Overpass (OpenStreetMap) + fallback catalog |
| Flight arrivals | AeroDataBox (RapidAPI) |
| Train arrivals | Transitland REST v2 |
| Events | Ticketmaster Discovery v2 + PredictHQ (conferences/expos) |
| Lifestyle areas | Overpass (offices, nightlife, restaurants, hotels) |

## Platform mapping notes

| iOS | Flutter |
|---|---|
| SwiftUI + ObservableObject | Widgets + ChangeNotifier |
| UserDefaults | shared_preferences |
| MapKit (`MKMapView`) | flutter_map + OSM tiles |
| `MKLocalSearch` venue search | Overpass queries (same categories) |
| UNUserNotificationCenter | flutter_local_notifications |
| RevenueCat purchases-ios + RevenueCatUI | purchases_flutter + purchases_ui_flutter |
| Info.plist build-setting keys | `--dart-define` (see below) |
| CLGeocoder timezone lookups | device-local timezone (spots are near the user) |

Like the iOS prototype, `LocationService` pins the app to a **forced Miami
test location** (`usesForcedTestLocation = true` in
`lib/services/location_service.dart`).

## Running

```sh
flutter pub get
flutter run \
  --dart-define=REVENUECAT_PUBLIC_API_KEY=appl_xxx \
  --dart-define=REVENUECAT_ENTITLEMENT_ID="RidePlanr Pro" \
  --dart-define=REVENUECAT_OFFERING_ID=default \
  --dart-define=REVENUECAT_MONTHLY_PRODUCT_ID=... \
  --dart-define=REVENUECAT_YEARLY_PRODUCT_ID=...
```

All `--dart-define`s are optional. Without the RevenueCat key the app runs in
local-preview subscription mode (exactly like the iOS app without
`REVENUECAT_PUBLIC_API_KEY` in build settings). The flight/train/event API keys
default to the same prototype fallback keys as the iOS sources and can be
overridden with `AERODATABOX_API_KEY`, `TRANSITLAND_API_KEY`,
`TICKETMASTER_API_KEY`, and `PREDICTHQ_API_KEY`.

### iOS setup notes

- Add `NSLocationWhenInUseUsageDescription` to `ios/Runner/Info.plist`
  ("DriverIntel uses your location to show local opportunities and weather around you.")
- Notifications and StoreKit need no extra setup beyond the standard plugin
  registration done by `flutter create`.

### Android setup notes

- Add `ACCESS_FINE_LOCATION`, `POST_NOTIFICATIONS`, and `INTERNET` permissions
  to `android/app/src/main/AndroidManifest.xml`.
