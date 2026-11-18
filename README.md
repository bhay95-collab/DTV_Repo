# TreadSync

A bare-bones iPhone app that reads distance from a RHYTHM FUN walking pad (`YPTM…`)
over Bluetooth and saves each session to Apple Health as an indoor walk or run.
Apple Fitness and any running app that imports from Apple Health then pick it up.

The treadmill supports the standard **Bluetooth FTMS** protocol (service `1826`,
Treadmill Data `2ACD`), so no reverse engineering is needed.

```
Treadmill ──FTMS over Bluetooth──▶ TreadSync (iPhone) ──HealthKit──▶ Apple Health ──▶ Fitness / Strava / …
```

## Layout

| Path | What |
|---|---|
| `ios/TreadSync/Core/FTMS.swift` | Decodes Treadmill Data packets |
| `ios/TreadSync/Core/WorkoutSession.swift` | Turns readings into a workout: distance, climb, estimated calories, odometer resets, Bluetooth dropouts |
| `ios/TreadSync/TreadmillManager.swift` | Bluetooth: finds the treadmill, subscribes, auto-reconnects |
| `ios/TreadSync/HealthKitWriter.swift` | Saves the workout to Apple Health |
| `ios/TreadSync/AppModel.swift`, `ContentView.swift` | Minimal UI |
| `ios/TreadSyncTests/` | Unit tests for the decoder and workout maths |
| `ios/project.yml` | XcodeGen spec that generates the Xcode project |
| `tools/ftms.py` | Same decoder in Python: `python3 tools/ftms.py "<hex>"` |
| `tools/ftms_logger.py` | Logs live treadmill data from a Mac/PC (`pip install bleak`) |

## 1. Check the treadmill actually sends data (5 min, optional)

Cheap pads sometimes advertise FTMS but send zeros. With the belt running and the vendor app closed:

1. nRF Connect → connect to `YPTM…` → Fitness Machine → **Treadmill Data** → tap the subscribe (↓ with a bar) button.
2. Walk for a minute. Copy a few of the hex values.
3. Decode them: `python3 tools/ftms.py "XX XX XX …"`. You want `speed_kmh` and `total_distance_m` changing.

## 2. Build and install (needs a Mac)

1. Install Xcode (App Store) and [Homebrew](https://brew.sh), then `brew install xcodegen`.
2. `cd ios && xcodegen && open TreadSync.xcodeproj`
3. In Xcode: select the **TreadSync** target → *Signing & Capabilities* → choose your Team
   (your Apple ID works) and change the bundle identifier to something unique, e.g. `com.yourname.treadsync`.
4. Plug in your iPhone, select it as the run destination and press ▶.
   First time: enable *Settings → Privacy & Security → Developer Mode* on the phone and trust the
   developer certificate under *Settings → General → VPN & Device Management*.
5. Optional: press ⌘U with a simulator selected to run the unit tests.

With a free Apple ID the app stops launching after 7 days; reconnect and press ▶ again.
With a paid Apple Developer membership an Xcode install lasts a year.

### Optional: install through TestFlight (private, never published)

Needs the paid Apple Developer Program. Builds expire after 90 days, so upload a new one before then.

1. **App Store Connect → Apps → + → New App.** Platform iOS, any name not already taken on the
   App Store (e.g. "TreadSync <your initials>"), your bundle ID, any SKU. This only creates a private
   record; nothing is submitted for review or published.
2. **Xcode:** select *Any iOS Device (arm64)* as the destination → **Product → Archive**.
3. In the Organizer window that opens: **Distribute App → TestFlight Internal Only** → Upload.
   Leave "Manage Version and Build Number" ticked so each upload gets a new build number.
4. Wait for the build to finish processing (5–30 min; you'll get an email).
5. **App Store Connect → your app → TestFlight → Internal Testing → +** to create a group and add
   yourself (and anyone else on your developer account).
6. On the iPhone, install the **TestFlight** app, accept the invite and install TreadSync.

Internal testing doesn't go through Beta App Review. Only *external* testers (people not on your
developer account) would need that.

## 3. Use it

1. Close the vendor app completely. The treadmill accepts only one connection at a time.
   Use the remote or the buttons on the pad to start and stop the belt.
2. Open TreadSync. Allow Bluetooth and Health access. It connects automatically.
3. Tap **Start workout**, walk, then **Finish & save to Apple Health**.
   Recording continues with the phone locked.

## Notes

- **Distance** comes from the treadmill's own odometer. If the treadmill doesn't send it, the app
  integrates belt speed instead. A treadmill reset mid-workout is handled.
- **Calories** are estimated using the ACSM walking/running equations, with your weight from
  Apple Health (75 kg if none). The treadmill's own calorie figure is ignored.
- **Climb** is estimated from incline × distance and saved as the workout's elevation gain.
- **Walk or run:** *Auto* picks Run when the average speed is 8 km/h or more.
- **Apple Watch:** don't also start an Indoor Walk on the watch, or you'll get two workouts.
- If your running app doesn't show the workout, check that its Apple Health import is turned on.
