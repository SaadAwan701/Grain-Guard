# GrainGuard Android

The native Flutter app is in `app/`. The supplied proposal and Stitch prototype are in the repository root and `grainguard/`.

## Windows setup

Run from the repository root. These commands assume Android Studio and the Android SDK are installed in their standard Windows locations.

```powershell
git clone --depth 1 --branch 3.50.0 https://github.com/flutter/flutter.git .tooling/flutter
git -C .tooling/flutter switch -c stable
. .\scripts\environment.ps1
flutter doctor -v
flutter doctor --android-licenses
dart pub global activate flutterfire_cli 1.5.0
npm.cmd ci
```

This checkout uses Flutter 3.50.0 (framework `ab2912035e`), Dart 3.14.0, and Android Studio's OpenJDK 21.0.9. The app compiles with Android SDK 36, Build Tools 36.0.0, NDK 28.2.13676358 and the checked-in Gradle 9.5.0 wrapper. It declares Android 7.0/API 24 as its minimum. The local toolchain also uses ADB 36.0.2, Node 24.14.0, npm 11.9.0, and Firebase CLI 15.16.0. Confirm the minimum Android version on the oldest pilot handset before freezing the release.

## Run the offline demo

```powershell
. .\scripts\environment.ps1
Set-Location app
flutter run --flavor staging
```

Open **Demo mode** on the welcome screen. **More** switches among Stable storage, Rising risk, Low battery, and Interrupted feed. Demo reports carry a simulated-data label.

## Exercise Firebase locally

From the repository root in one terminal:

```powershell
. .\scripts\environment.ps1
firebase.cmd emulators:start --project demo-grainguard --only auth,database
```

From the repository root in a second terminal:

```powershell
. .\scripts\environment.ps1
node firebase/fixture.mjs seed
Set-Location app
flutter run --flavor staging --dart-define=GG_EMULATORS=true
```

Sign in with the local viewer credentials printed by the seed command. The bin should show **Waiting for first reading**. Run `node firebase/fixture.mjs publish rehearsal-1` from the root in another terminal to publish a reading. Run the same command again to exercise a retry. Use `node firebase/fixture.mjs backfill rehearsal-backfill` to add a history-only sample.

The default emulator host `10.0.2.2` is for Android Virtual Devices. For a USB-connected phone use `adb reverse tcp:9099 tcp:9099`, `adb reverse tcp:9000 tcp:9000` and `--dart-define=GG_EMULATOR_HOST=127.0.0.1`.

## Provision staging and production

Register `pk.grainguard.app.staging` and `pk.grainguard.app` in distinct team-owned Spark projects. Enable Email/Password Auth and Realtime Database. Deploy the repository rules to each explicitly selected project. Provision invited users, bin metadata, memberships and a separate device writer identity from trusted administrator tooling. Supply the Firebase client options as a local `--dart-define-from-file` JSON file. Firebase options may be obtained from FlutterFire CLI or the Android app registration.

```json
{
  "GG_STAGING_API_KEY": "...",
  "GG_STAGING_APP_ID": "...",
  "GG_STAGING_PROJECT_ID": "...",
  "GG_STAGING_SENDER_ID": "...",
  "GG_STAGING_DATABASE_URL": "https://...",
  "GG_SUPPORT_CONTACT": "..."
}
```

Use the `GG_PRODUCTION_` prefix for the production client options. Store the release keystore outside source control, and use a local `app/android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. The production release variant requires that file.

Add a `label` and `grainType` (`wheat` or `rice`) to each operator membership at `memberships/{operatorUid}/{deviceId}`. Use the same grain type in `devices/{deviceId}/meta` when provisioning or changing a lot. Older memberships without a grain type appear under Wheat. Set `deviceWriters/{deviceId}` to the publisher's Firebase Auth UID.

Set `expectedCadenceSec` in device metadata to the ESP32's actual publishing interval. Optionally set `offlineTimeoutSec` to an integer longer than that interval. For a publisher sending every five seconds, a 20-second timeout marks its last reading stale after 20 seconds. With no valid override, the app uses three times the expected cadence. The app listens for updates and uses a local timer to detect stale data.

## Verification and APK

```powershell
. .\scripts\environment.ps1
firebase.cmd emulators:exec --project demo-grainguard --only auth,database 'npm test'
Set-Location app
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --release --flavor staging --dart-define=GG_EMULATORS=true
```

The staging APK uses development signing and can run its demo offline. For the Android integration test, start a clean Firebase emulator, seed it before publishing, clear the staging application's Android data if it was used before, and run `flutter test integration_test/live_feed_test.dart -d emulator-5554 --flavor staging --dart-define=GG_EMULATORS=true`.

The 12 November 2026 staging build passed analyzer checks, eight Flutter tests and three Firebase rules tests. The API 36.1 Android emulator installed the development-signed APK, opened the demo with network access disabled, rotated the kernel, and updated a signed-in bin from **Waiting for first reading** to **Live readings** with a 67% device battery after an authenticated fixture publish. PDF and CSV exports opened the Android share sheet. The staging APK SHA-256 is `8B51BA7BAA4E17457E7BC5CDD0D591090A9A643CBD3628AEEAAC745FB8D99219`.

Build the production artifact with `flutter build apk --release --flavor production --dart-define-from-file=config/production.json`. Verify it with `apksigner verify --verbose --print-certs` and `Get-FileHash -Algorithm SHA256`, then clean-install and upgrade the exact artifact on the target phones. Confirm the physical phones, venue connectivity, release signing ownership and installation channel.

## Publisher handoff

The current cloud staging project is `grainguard-8248c`. Its first bin is `GG001` with lot `WHEAT-001`. Build the cloud staging APK from `app/` with `flutter build apk --release --flavor staging --dart-define-from-file=config/staging.json`. The operator and publisher sign-in details are stored locally in the ignored `app/config/first-bin-credentials.json`. Use the publisher account on the ESP32 and the operator account on the phone. The initial five-second cadence and twenty-second offline timeout are configurable in the bin metadata. On this Windows setup, an authorized Firebase CLI owner can rerun provisioning from the repository root with `node firebase/provision-first-bin.mjs <Firebase CLI account email>`.

Use schema version 1. Write a stable sample ID to `devices/{deviceId}/lots/{lotId}/samples/{sampleId}`. Advance `devices/{deviceId}/latest` with the identical sample in a single atomic multi-path update, only for the active lot and a newer measurement. Backfills write history only. On a retry, read the history item first and treat the same stored measurement as already accepted. Use UTC epoch milliseconds for `measuredAtMs` and the RTDB server timestamp for `receivedAtMs`.

The firmware can sign in over HTTPS using the [Firebase Auth REST API](https://firebase.google.com/docs/reference/rest/auth#section-sign-in-email-password). Keep the device account credentials in the device's local configuration and refresh its ID token when it expires. Use that token for authenticated requests to the [Realtime Database REST API](https://firebase.google.com/docs/database/rest/auth). The following is an example body for a single root `PATCH`. Use the actual IDs, time and measurements from the ESP32 in each upload.

```json
{
  "devices/GG001/latest": {
    "schemaVersion": 1,
    "deviceId": "GG001",
    "lotId": "WHEAT-001",
    "sampleId": "GG001-1794592800000",
    "measuredAtMs": 1794592800000,
    "receivedAtMs": { ".sv": "timestamp" },
    "sensors": { "temperatureC": 30.2, "relativeHumidityPct": 75.4 }
  },
  "devices/GG001/lots/WHEAT-001/samples/GG001-1794592800000": {
    "schemaVersion": 1,
    "deviceId": "GG001",
    "lotId": "WHEAT-001",
    "sampleId": "GG001-1794592800000",
    "measuredAtMs": 1794592800000,
    "receivedAtMs": { ".sv": "timestamp" },
    "sensors": { "temperatureC": 30.2, "relativeHumidityPct": 75.4 }
  }
}
```

The optional sensor fields are `temperatureC`, `relativeHumidityPct`, `co2Ppm`, `gasResistanceOhm`, `acousticEvents`, and `acousticWindowSec`. Acoustic counts require a valid window. The optional battery object accepts `percent`, `voltageMv`, and `chargeState`. Omit unavailable fields and keep measured zero values. Confirm cadence, battery sampling time, discharge thresholds and quality flag vocabulary with the node team before freezing the contract.

## Live alerts and storage estimates

The live dashboard uses the following inspection rules. They are operational screening thresholds for ordinary grain storage. Placement, ventilation, calibration and planned CO₂ treatment affect the interpretation.

| Signal | Live rule |
| --- | --- |
| CO₂ | Below 600 ppm does not trigger a CO₂ alert. From 600 to 1,499 ppm, three consecutive readings trigger an inspection alert. At 1,500 ppm or above, one fresh reading triggers an urgent inspection alert. Three readings at or below 550 ppm rearm the CO₂ episode. [Dirk Maier's grain storage guidance](https://www.grainjournal.com/article/209179/stored-grain-management-carbon-dioxide-monitoring) |
| Relative humidity | Above 65% on three consecutive readings triggers inspection. Three readings at or below 63% rearm the episode. This is bin air RH. [University of Kentucky grain storage guidance](https://bae.mgcafe.uky.edu/extension/grain-storage-systems) |
| Temperature | Displayed and trended. The storage allowance uses measured grain temperature together with grain moisture. |
| Gas resistance and acoustic activity | Displayed and trended. Grain quality limits need device and lot calibration. |
| Battery | Two consecutive readings at or below 20% open a device alert. A reading at or below 10% during an active low battery episode can escalate it. A reading at or above 24% rearms the episode. |
| Feed | The bin's configurable timeout raises a stale-feed alert. |

An alert appears in the in-app inbox and can post to Android while its bin is open. Use **Alerts → Manage Android notifications** to allow the Android channel. A closed-app push needs a trusted event processor and Firebase Cloud Messaging sender. [FCM server environment](https://firebase.google.com/docs/cloud-messaging/server-environment)

Remaining storage days are a planning estimate for steady conditions. In `devices/{deviceId}/meta/storageEstimate`, provide the current `lotId`, `storedSinceMs` (UTC epoch milliseconds), measured `grainMoisturePctWetBasis`, measured `grainTemperatureC`, and `constantConditionsConfirmed: true` after verifying that the conditions represent the lot since storage began. GrainGuard selects the next warmer and wetter supported cell in Table 3 and subtracts elapsed storage time. The table targets approximately 0.5% dry matter loss. The app leaves censored cells, unsupported ranges, and missing measurements unavailable. It does not derive grain moisture from air humidity or dry matter loss from CO₂ concentration. [University of Arkansas Extension, FSA1058](https://www.uaex.uada.edu/publications/pdf/FSA1058.pdf)
