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

Build the production artifact with `flutter build apk --release --flavor production --dart-define-from-file=config/production.json`. Verify it with `apksigner verify --verbose --print-certs` and `Get-FileHash -Algorithm SHA256`, then clean-install and upgrade the exact artifact on the target phones. Confirm the physical phones, venue connectivity, release signing ownership and installation channel.

## Publisher handoff

Use schema version 1. Write a stable sample ID to `devices/{deviceId}/lots/{lotId}/samples/{sampleId}`. Advance `devices/{deviceId}/latest` with the identical sample in a single atomic multi-path update, only for the active lot and a newer measurement. Backfills write history only. On a retry, read the history item first and treat the same stored measurement as already accepted. Use UTC epoch milliseconds for `measuredAtMs` and the RTDB server timestamp for `receivedAtMs`.

The optional sensor fields are `temperatureC`, `relativeHumidityPct`, `co2Ppm`, `gasResistanceOhm`, `acousticEvents`, and `acousticWindowSec`. Acoustic counts require a valid window. The optional battery object accepts `percent`, `voltageMv`, and `chargeState`. Omit unavailable fields and keep measured zero values. Confirm cadence, battery sampling time, discharge thresholds and quality flag vocabulary with the node team before freezing the contract.

Live risk thresholds, calibrated grain moisture, storage life and dry matter loss remain gated pending project validation and a confirmed payload. Demo estimates and the demo risk evaluator are illustrative.
