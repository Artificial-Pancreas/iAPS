# Autotune Fix for AutoISF / DynamicISF

## Background

iAPS includes an autotune system adapted from the [oref0](https://github.com/openaps/oref0) algorithm.
Its purpose is to automatically tune three parameters over time using real-world glucose data:

- **Basal profile** — the hourly background insulin rates
- **ISF (Insulin Sensitivity Factor)** — how much one unit of insulin lowers BG (mg/dL/U)
- **CR (Carb Ratio)** — how many grams of carbs one unit of insulin covers (g/U)

The algorithm works by computing *deviations* for every 5-minute glucose interval: the difference
between the actual BG change and the BG change that was expected based on the insulin on board.
If deviations are consistently positive at a given time of day, basals or ISF are too low; if
consistently negative, too high.

---

## The Problem

### How oref0 autotune computes Blood Glucose Impact (BGI)

For each 5-minute interval, autotune-prep calculates:

```
expectedBGI = avgIOB × profile.sens × (5 / 60)
deviation   = actual_BG_delta − expectedBGI
```

`profile.sens` is the **static ISF** from the pump profile — a single scalar value that is the
same for every calculation, regardless of time of day or loop cycle.

### Why this breaks under AutoISF and DynamicISF

AutoISF and DynamicISF are dynamic algorithms that recalculate and apply a **different ISF on
every loop cycle** (approximately every 5 minutes). The actual ISF used (`Reasons.isf`) is stored
in CoreData after each loop run, and frequently differs substantially from `profile.sens`.

When the actual applied ISF is, say, 30 mg/dL/U but `profile.sens` is 50 mg/dL/U:

```
expectedBGI (wrong) = IOB × 50 × (5/60)   ← uses static profile ISF
expectedBGI (correct) = IOB × 30 × (5/60)  ← uses actual loop ISF
```

The deviation computed by autotune-prep is therefore wrong by:

```
error = IOB × (profile.sens − actual_ISF) × (5/60)
```

Over thousands of data points, this systematic error biases:

- **Basal suggestions** — autotune sees unexplained positive deviations and incorrectly raises
  basal rates (when in reality the dynamic algorithm was simply using a lower ISF than the profile)
- **ISF inference** — oref0's deviation classification cannot recover a reliable ISF signal from
  data where the true ISF varies every 5 minutes

### What was already in place (harm-reduction only)

A prior commit introduced `categorizeUamAsBasal = true` when a dynamic algorithm is active. This
routes unannounced-meal (UAM) data into the basal bucket rather than the ISF bucket, reducing noise
in the ISF dataset. It also forced `onlyAutotuneBasals = true` in the settings, discarding the ISF
and CR outputs before they reached the profile.

This was harm reduction, not a fix: the basal deviation calculation was still wrong, and the ISF
output was silently discarded rather than being computed correctly.

---

## The Fix

Three coordinated changes correct both the basal and ISF calculations when a dynamic algorithm is
active.

### 1. Build a per-hour actual ISF schedule from CoreData Reasons

**File:** `FreeAPS/Sources/APS/OpenAPS/OpenAPS.swift`
**Function:** `buildReasonsISFSchedule() -> (schedule: RawJSON, median: Double?)`

Every loop run saves the actual ISF it applied to the CoreData `Reasons` entity
(`saveSuggestion.isf`, `saveSuggestion.ratio`). This function queries the last 14 days of Reasons
entries and builds a per-hour median ISF schedule.

#### Data filtering

Only entries where `sensitivityRatio` (the `ratio` field) is within ±0.15 of 1.0 are included.
A ratio near 1.0 means the dynamic algorithm made little adjustment — close to pure basal conditions.
Entries during meals or exercise (where the dynamic ISF deviates most from the underlying basal ISF)
are excluded because they reflect a transient metabolic state rather than the baseline ISF.

```
isf > 10 mg/dL/U AND isf < 600 mg/dL/U   ← sanity bounds
abs(ratio − 1.0) ≤ 0.15                   ← near-basal condition filter
```

#### Minimum data requirements

- At least **12 distinct hours of the day** must have **3 or more qualifying data points** each.
- If this threshold is not met, the function returns `.empty` and the fix is silently skipped,
  falling back to the pre-fix behaviour. This handles new installs or users who have not yet
  accumulated enough Reasons history.

#### Per-hour median and interpolation

For each of the 24 hours, the median of all qualifying `isf` values for that hour is computed.
Hours that lack sufficient data are filled by nearest-neighbour interpolation (scanning outward
from the sparse hour in both directions around the clock). This ensures a complete 24-entry
schedule is always produced when the function returns successfully.

#### Output format

```json
{
  "0":  42.5,
  "1":  41.0,
  "2":  40.5,
  ...
  "23": 43.0
}
```

The function also returns the overall median across all 24 hourly medians for use as a single
scalar fallback.

---

### 2. Override `profile.sens` in autotune-prep before the bundle runs

**File:** `FreeAPS/Resources/javascript/prepare/autotune-prep.js`

The `generate()` wrapper function (which iAPS calls before invoking the minified oref0 bundle)
now accepts an 8th argument: `isf_schedule = {}`.

When a schedule with ≥ 12 valid hourly values is provided, the wrapper computes the overall median
and replaces `profile_data.sens` and `pumpprofile_data.sens` with that value before calling
`freeaps_autotunePrep(inputs)`:

```javascript
// New 8th parameter
function generate(..., isf_schedule = {}) {
    ...
    if (isf_schedule && typeof isf_schedule === 'object') {
        var isfValues = Object.values(isf_schedule).filter(v => typeof v === 'number' && v > 10 && v < 600);
        if (isfValues.length >= 12) {
            var sortedISF = isfValues.slice().sort((a, b) => a - b);
            var medianISF = sortedISF[Math.floor(sortedISF.length / 2)];
            profile_data.sens = medianISF;
            pumpprofile_data.sens = medianISF;
        }
    }
    ...
    return freeaps_autotunePrep(inputs);
}
```

**Why a single median rather than per-hour values?**

The oref0 bundle processes all glucose data in a single pass and uses one `profile.sens` scalar
throughout. Passing per-hour values to the bundle would require forking the bundle itself.
Using the overall median actual ISF substantially reduces the systematic bias — particularly
for users whose dynamic ISF differs significantly from their profile ISF across the board —
without requiring any changes to the vendored oref0 code.

This corrects the BGI formula to:

```
expectedBGI ≈ avgIOB × actual_median_ISF × (5/60)
deviation   = actual_BG_delta − expectedBGI
```

The deviations are now centred around zero (instead of being systematically biased), which makes
the basal profile suggestions from `autotuneRun` reliable.

---

### 3. Replace autotune's inferred ISF output with the direct Reasons measurement

**File:** `FreeAPS/Sources/APS/OpenAPS/OpenAPS.swift`
**Location:** `autotune()`, after `autotuneRun()` returns

After the oref0 bundle produces its `autotuneResult` JSON, the Swift `Autotune` struct is
constructed from it. When a dynamic algorithm is active and `buildReasonsISFSchedule()` returned
a valid median, the `sensitivity` field is overwritten:

```swift
if var autotune = Autotune(from: autotuneResult) {
    if dynamicAlgorithmActive, let medianISF = reasonsMedianISF {
        autotune.sensitivity = Decimal(medianISF)
    }
    self.storage.save(autotuneResult, as: Settings.autotune)
    promise(.success(autotune))
}
```

Note that `autotuneResult` (the raw JSON) is saved *before* the struct is patched. This preserves
the oref0 bundle's original output as the `previousAutotuneResult` input for the next run, keeping
the bundle's internal convergence loop intact. Only the Swift-layer representation shown to the user
and passed to `makeProfiles` carries the corrected ISF value.

**Why not use the bundle's ISF?**

oref0 infers ISF by looking at deviation patterns during periods of high IOB. When ISF changes
every 5 minutes, the deviation signal is dominated by noise from those changes rather than from a
true basal/ISF mismatch. The Reasons entries record the exact `isf` value the algorithm computed
and applied for that loop cycle — this is ground truth, not an inference.

---

## Data Flow Diagram

```
autotune() called
│
├── Load: pumpHistory, glucose, profile, pumpProfile, carbs
│
├── Detect dynamic algorithm (autoisf || useNewFormula)
│
├── [dynamic] buildReasonsISFSchedule()
│   ├── CoreDataStorage().fetchReasons(interval: 14 days ago)
│   ├── Filter: isf > 10, isf < 600, abs(ratio − 1.0) ≤ 0.15
│   ├── Group by hour-of-day, compute per-hour median
│   ├── Require ≥ 12 hours with ≥ 3 data points
│   ├── Interpolate missing hours from neighbours
│   └── Return (schedule JSON {"0": 42.5, …}, overallMedian)
│
├── autotunePrepare(…, isfSchedule: scheduleJSON)
│   └── calls generate() in autotune-prep.js
│       ├── [if schedule has ≥ 12 entries]
│       │   └── profile_data.sens = pumpprofile_data.sens = median(schedule values)
│       └── freeaps_autotunePrep(inputs)  ← oref0 bundle, now uses actual ISF
│
├── autotuneRun(preparedData, previousAutotune, pumpProfile)
│   └── oref0 bundle: basal suggestions are now based on correct deviations
│
└── Autotune(from: autotuneResult)
    ├── [dynamic && reasonsMedianISF != nil]
    │   └── autotune.sensitivity = Decimal(reasonsMedianISF)  ← direct measurement
    └── promise(.success(autotune))
```

---

## Supporting Changes

### `FreeAPS/Sources/Models/Autotune.swift`

`sensitivity` changed from `let` to `var` to allow the post-processing patch in `autotune()`.

### `AutotuneConfigStateModel.swift`

The forced `settingsManager.settings.onlyAutotuneBasals = true` assignment (which was previously
applied automatically whenever a dynamic algorithm was detected) has been removed. Since ISF is
now a direct measurement from Reasons data rather than an unreliable inference, forcing basal-only
mode is no longer necessary as a safety net. The user retains control of the `onlyAutotuneBasals`
toggle.

The `dynamicAlgorithmActive` flag is retained for UI display purposes.

### `AutotuneConfigRootView.swift`

The info banner that previously locked out the `onlyAutotuneBasals` toggle and stated ISF tuning
was disabled has been replaced with:

- The toggle is now always visible (user-controllable)
- When `dynamicAlgorithmActive`, an informational note explains that ISF is measured directly from
  loop data (not inferred from deviations), and advises that CR tuning may still be less reliable
  under dynamic algorithms

---

## Limitations and Known Gaps

### CR (Carb Ratio) tuning is still unreliable under dynamic algorithms

The carb-absorption model in oref0 assumes ISF is static when computing the expected BG contribution
from carb absorption. With dynamic algorithms, the actual ISF varies, making the carb-absorption
signal noisy. `onlyAutotuneBasals` (default: on for dynamic users, user-adjustable) should remain
enabled unless the user specifically wants to review the ISF value.

### Single median ISF, not per-hour

The bundle receives one scalar `profile.sens` for all data. The per-hour schedule built by
`buildReasonsISFSchedule()` is used to derive that scalar (median of 24 hourly medians), and is
also available for future use (e.g., per-hour BGI correction or a richer ISF schedule display in
the UI). Passing per-hour ISF to the oref0 bundle would require modifying the vendored minified
bundle, which is out of scope.

### 14-day window and minimum data threshold

Users who have just enabled a dynamic algorithm, recently reset their device, or have a loop that
runs infrequently may not accumulate 12 hours of qualifying Reasons data within the 14-day window.
In this case `buildReasonsISFSchedule()` returns `.empty` and the fix is not applied — the run
proceeds using the old (biased) `profile.sens`. No error is raised; a debug log entry is written.

### `sensitivityRatio` filter threshold (±0.15)

The ±0.15 ratio filter was chosen to capture near-basal conditions while excluding significant
meal and exercise events. It may be worth tuning based on real-world data from dynamic algorithm
users. A tighter threshold (e.g. ±0.10) would give a purer basal ISF signal but reduce the number
of qualifying data points; a looser threshold (e.g. ±0.25) gives more data but with more noise.

---

## Files Changed

| File | Change |
|------|--------|
| `FreeAPS/Sources/APS/OpenAPS/OpenAPS.swift` | Added `buildReasonsISFSchedule()`; modified `autotune()` to build and pass ISF schedule and patch ISF output; added `isfSchedule` parameter to `autotunePrepare()` |
| `FreeAPS/Resources/javascript/prepare/autotune-prep.js` | Added 8th `isf_schedule` parameter; override `profile_data.sens` / `pumpprofile_data.sens` with actual median ISF when schedule is available |
| `FreeAPS/Sources/Models/Autotune.swift` | `sensitivity: let` → `var` |
| `FreeAPS/Sources/Modules/AutotuneConfig/AutotuneConfigStateModel.swift` | Removed forced `onlyAutotuneBasals = true`; updated comments |
| `FreeAPS/Sources/Modules/AutotuneConfig/View/AutotuneConfigRootView.swift` | Restored `onlyAutotuneBasals` toggle for dynamic algorithm users; updated info banner text |

---

## CoreData Schema Reference

The `Reasons` entity (`Core_Data.xcdatamodeld`) stores one row per loop cycle:

| Attribute | Type | Description |
|-----------|------|-------------|
| `date` | Date | Timestamp of the loop run |
| `isf` | Decimal | Actual ISF the algorithm computed and applied (mg/dL/U) |
| `ratio` | Decimal | `sensitivityRatio` — the multiplier applied to profile ISF (1.0 = no adjustment) |
| `iob` | Decimal | Insulin on board at loop time |
| `cob` | Decimal | Carbs on board at loop time |
| `glucose` | Decimal | Current BG reading |
| `cr` | Decimal | Carb ratio used |
| `tdd` | Decimal | Total daily dose |

The relationship between `isf` and `ratio` is:

```
isf = profile_isf × ratio     (approximately — AutoISF uses more complex adjustments)
```

A `ratio` of 1.0 means the dynamic algorithm made no adjustment to the profile ISF.
The ±0.15 filter on `ratio` therefore selects loop cycles where the dynamic adjustment
was 15% or less — the closest available proxy for "what ISF would be correct if the patient
were in a pure fasting basal state."

`CoreDataStorage.fetchReasons(interval:)` returns entries sorted descending by date with a
predicate of `date > interval`.
