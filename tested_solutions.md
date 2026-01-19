# Libre 2+ Sensor Expiration Fix - Tested Solutions

## Issue
The homescreen displays incorrect sensor remaining time (e.g., `-1d20h` instead of `13d16h`).

- **Libre 2**: 14.5 days (14d 12h) = 20,880 minutes
- **Libre 2+**: 15.5 days (15d 12h) = 22,320 minutes

The sensor serial starts with "301" for Libre 2+.

---

## Solution 1: Dynamic values (sensorMaxMinutesWearTime)
**Files:** `KnownPlugins.swift`

**Approach:** Read `sensorInfoObservable.sensorMaxMinutesWearTime` directly from LibreTransmitter.

```swift
let maxMinutes = libreManager.sensorInfoObservable.sensorMaxMinutesWearTime
if maxMinutes > 0 {
    return TimeInterval(maxMinutes * 60)
}
```

**Result:** ❌ FAILED
- `sensorMaxMinutesWearTime` is 0 when `cgmExpirationByPluginIdentifier` is called
- The value is set later in `setObservables()` which runs asynchronously

---

## Solution 2: Calculate from expiresAt - activatedAt
**Files:** `KnownPlugins.swift`

**Approach:** Calculate total lifetime from the sensor dates.

```swift
if let activatedAt = sensorInfo.activatedAt,
   let expiresAt = sensorInfo.expiresAt {
    return expiresAt.timeIntervalSince(activatedAt)
}
```

**Result:** ❌ FAILED
- Same timing issue: `activatedAt` and `expiresAt` are nil when function is called
- They are set in `setObservables()` which runs asynchronously on main queue

---

## Solution 3: Use sensorMinutesSinceStart + sensorMinutesLeft
**Files:** `KnownPlugins.swift`

**Approach:** Calculate total lifetime from minutes since start + minutes left.

```swift
let minutesLeft = sensorInfo.sensorMinutesLeft
let minutesSinceStart = sensorInfo.sensorMinutesSinceStart
if minutesLeft > 0, minutesSinceStart > 0 {
    return TimeInterval((minutesSinceStart + minutesLeft) * 60)
}
```

**Result:** ❌ FAILED
- Same timing issue: both values are 0 when function is called
- Set asynchronously in `setObservables()`

---

## Solution 4: Hardcoded values based on sensorSerial prefix
**Files:** `KnownPlugins.swift`, `DeviceDataManager.swift`

**Approach:** Check if sensor serial starts with "301" for Libre 2+.

```swift
let serial = libreManager.sensorInfoObservable.sensorSerial
guard !serial.isEmpty, serial != "-" else {
    return nil
}
if serial.hasPrefix("301") {
    return 15.5 * secondsOfDay  // Libre 2+
} else {
    return 14.5 * secondsOfDay  // Libre 2
}
```

**Result:** ❌ FAILED
- `sensorSerial` is also empty ("") when function is called
- Set asynchronously in `setObservables()`

---

## Solution 5 (TO TEST): Use UserDefaults.standard.preSelectedSensor
**Files:** `KnownPlugins.swift`

**Approach:** The sensor info is stored in UserDefaults during pairing, before any async operations.

```swift
if let sensorName = UserDefaults.standard.preSelectedSensor?.sensorName,
   !sensorName.isEmpty {
    if sensorName.hasPrefix("301") {
        return 15.5 * secondsOfDay  // Libre 2+
    } else {
        return 14.5 * secondsOfDay  // Libre 2
    }
}
```

**Rationale:**
- `preSelectedSensor` is set during sensor pairing in `Libre2DirectSetup.swift`
- It's persisted to UserDefaults immediately
- Contains `sensorName` (the serial) and `maxAge` (in minutes)
- Should be available immediately, unlike `sensorInfoObservable` properties

**Status:** 🔄 PENDING TEST

---

## Root Cause Analysis

The core issue is timing:

1. `cgmExpirationByPluginIdentifier()` is called in:
   - `setupCGM()` - when app starts
   - `cgmManagerDidUpdateState()` - when CGM state updates

2. `sensorInfoObservable` properties are set in:
   - `setObservables()` - runs on `DispatchQueue.main.async`

3. The function is called BEFORE `setObservables()` completes, so all observable properties are at their default values (0 or "").

The solution is to use data that's available synchronously, like `UserDefaults.standard.preSelectedSensor` which is set during sensor pairing.
