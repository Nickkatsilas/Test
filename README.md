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

## What gets exported
Each export sends **two CSVs** in two POSTs to the same URL, distinguished by the `X-Dataset` header:

**`daily`** (`X-Dataset: daily`) - one row per day/metric/stat:
```
date,metric,stat,value,unit
2026-09-28,steps,sum,10432.0,count
2026-09-28,body_mass,avg,82.4,kg
2026-09-28,dietary_energy,sum,2140.0,kcal
```
Upsert on `(date, metric, stat)`.

**`samples`** (`X-Dataset: samples`) - every individual reading/event with its source app:
```
start,end,metric,value,unit,source
2026-09-28T07:12:03-04:00,2026-09-28T07:12:03-04:00,body_mass,82.4,kg,RENPHO
2026-09-28T12:30:00-04:00,2026-09-28T12:30:00-04:00,dietary_energy,640.0,kcal,Lose It!
```
Upsert/dedupe on `(start, end, metric, source, value)`. Includes weight and body composition, blood pressure, glucose, temperature, blood oxygen, every dietary entry (calories, macros, and ~35 micronutrients), sleep segments, workouts, and Health events (high/low heart rate, irregular rhythm, low cardio fitness, walking steadiness, loud audio, mindful sessions).

Lose It! and Renpho only appear if they are syncing into Apple Health (Lose It! > Settings > Apple Health; Renpho > Settings > Apple Health). Renpho writes weight, BMI, body fat and lean mass; its other readings (muscle, water, bone) are not Health types and can't be exported by any HealthKit app.

The daily file has ~100 metrics: activity, heart/vitals, body, mobility, running/cycling, respiratory, nutrition, audio exposure, sleep stages (hours, dated by wake day) and per-type workout count/minutes/energy. Add more in `HealthExporter.specs`. Not included: ECG waveforms, clinical records, cycle tracking, medications, GPS routes.

## Dashboard endpoint contract
`POST <your URL>` with the CSV as the raw body:

- `Content-Type: text/csv`
- `Authorization: Bearer <token>` (if set)
- `X-Dataset`: `daily` or `samples`
- `X-Filename`, `X-Date-Range` (`YYYY-MM-DD..YYYY-MM-DD`)

Respond with any 2xx on success. Each upload overlaps previous ones (last N days), so upsert rather than append.

## How the automatic export works (and its limits)
iOS doesn't allow exact-time background jobs, so the app uses every trigger available:
1. HealthKit background delivery (`.immediate`) for steps, heart rate, active energy, HRV, sleep and workouts
2. A background app refresh request (asked for every ~1h; iOS decides the real timing)
3. The moment the phone is unlocked (if the app is still alive in the background)
4. Whenever you open the app

After a successful upload the next automatic one waits 3 hours (`minInterval` in `ExportCoordinator.swift`); failed or locked-phone attempts retry on the next trigger. So your dashboard gets fresh same-day data several times a day.

Health data is encrypted while the phone is locked, so a run on a locked phone can't read it and waits for the next trigger. Keep **Background App Refresh** on and don't force-quit the app. A local copy of each CSV is saved to the app's Files folder.

## Note
This was written without access to Xcode, so it has not been compiled. Expect to fix a small build error or two on first build.
