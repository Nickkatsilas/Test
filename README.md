# Health Export

A minimal iOS app that reads your Apple Health data, builds a CSV once a day, and POSTs it to your AI dashboard.

## Build & ship to TestFlight (needs a Mac with Xcode 15+)

```bash
brew install xcodegen
xcodegen generate          # creates HealthExport.xcodeproj from project.yml
open HealthExport.xcodeproj
```

1. In `project.yml` (or Xcode > Signing & Capabilities) set your **Team ID**. Change `PRODUCT_BUNDLE_IDENTIFIER` if `com.lapota.healthexport` is taken (keep `BGTaskSchedulerPermittedIdentifiers` = `<bundle id>.refresh`, and `refreshTaskID` in `ExportCoordinator.swift`, in sync).
2. In App Store Connect, create an app record with that bundle ID.
3. In Xcode: select **Any iOS Device (arm64)** > Product > **Archive** > Distribute App > **App Store Connect** > Upload.
4. Add yourself as an internal tester in TestFlight and install.

HealthKit entitlements (including background delivery) are enabled automatically by Xcode's automatic signing.

## First run
Open the app, paste your dashboard URL (must be `https://`) and optional API token, tap **Export now**, and approve the Health permissions. To backfill history, raise "Days included" (up to 365) and export once, then set it back to ~7.

## CSV format
Long format, one row per day/metric/stat:

```
date,metric,stat,value,unit
2026-09-28,steps,sum,10432.0,count
2026-09-28,heart_rate,avg,71.2,count/min
2026-09-28,sleep_rem,sum,1.6,hr
```
Metrics: activity, heart/vitals, body, mobility, nutrition, audio exposure, sleep stages (hours, dated by wake day), and per-type workout count/minutes/energy. Add more in `HealthExporter.specs`. This is daily aggregates, not every raw sample.

## Dashboard endpoint contract
`POST <your URL>` with the CSV as the raw body:

- `Content-Type: text/csv`
- `Authorization: Bearer <token>` (if set)
- `X-Filename`, `X-Date-Range` (`YYYY-MM-DD..YYYY-MM-DD`)

Respond with any 2xx on success. Each upload overlaps previous ones (last N days), so **upsert on `(date, metric, stat)`** rather than appending.

## How "automatic daily" works (and its limits)
iOS doesn't allow exact-time background jobs. The app tries three triggers, and exports at most once per calendar day after a successful upload:
1. HealthKit background delivery (wakes the app hourly when new steps/heart rate/sleep arrive)
2. A background app refresh request (~every 6h at the earliest)
3. Whenever you open the app

Health data is encrypted while the phone is locked, so an overnight run on a locked phone can't read it; it completes on the next wake while unlocked. Keep **Background App Refresh** on and don't force-quit the app. A local copy of each CSV is also saved to the app's Files folder.

## Note
This was written without access to Xcode, so it has not been compiled. Expect to fix a small build error or two on first build.
