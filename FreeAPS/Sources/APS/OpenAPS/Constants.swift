extension OpenAPS {
    enum Bundle {
        static let oref0 = "bundle/oref0-bridge.js"
    }

    enum Test {
        static let test = "test/test.js"
    }

    enum Middleware {
        static let determineBasal = "middleware/determine_basal.js"
    }

    enum Settings {
        static let preferences = "preferences.json"
        static let autotune = "settings/autotune.json"
        static let settings = "settings/settings.json"
        static let bgTargets = "settings/bg_targets.json"
        static let insulinSensitivities = "settings/insulin_sensitivities.json"
        static let basalProfile = "settings/basal_profile.json"
        static let carbRatios = "settings/carb_ratios.json"
        static let tempTargets = "settings/temptargets.json"
        static let model = "settings/model.json"
        static let contactTrick = "settings/contact_trick.json"
        static let autoisf = "settings/autoisf.json"
    }

    enum Monitor {
        static let pumpHistory = "monitor/pumphistory-24h-zoned.json"

        static let carbHistory = "monitor/carbhistory.json"
        static let clock = "monitor/clock-zoned.json"

        static let meal = "monitor/meal.json"
        static let glucose = "monitor/glucose.json"
        static let iob = "monitor/iob.json"
        static let cgmState = "monitor/cgm-state.json"

//        static let dynamicVariables = "monitor/dynamicVariables.json"
        static let alertHistory = "monitor/alerthistory.json"
        static let statistics = "monitor/statistics.json"
    }

    enum Enact {
        static let suggested = "enact/suggested.json"
        static let outcome = "enact/outcome.json"
    }

    enum Upload {
        static let latestTreatments = "upload/latest-treatments.json"
        static let recentPumphistory = "upload/recent-pumphistory.json"
        static let recentSuggested = "monitor/recent-suggested.json"
        static let recentEnacted = "monitor/recent-enacted.json"
    }

    enum Nightscout {
        static let uploadedPumphistory = "upload/uploaded-pumphistory.json"
        static let uploadedCarbs = "upload/uploaded-carbs.json"
        static let uploadedTempTargets = "upload/uploaded-temptargets.json"
        static let uploadedGlucose = "upload/uploaded-glucose.json"
        static let uploadedCGMState = "upload/uploaded-cgm-state.json"
        static let uploadedPodAge = "upload/uploaded-pod-age.json"
        static let uploadedProfile = "upload/uploaded-profile.json"
        static let uploadedProfileToDatabase = "upload/uploaded-profile_database.json"
        static let uploadedPreferences = "upload/uploaded-preferences.json"
        static let uploadedSettings = "upload/uploaded-settings.json"
        static let uploadedManualGlucose = "upload/uploaded-manual-readings.json"
        static let notUploadedOverrides = "upload/not-uploaded-overrides.json"
        static let uploadedPumpSettings = "upload/uploaded-pump_settings.json"
        static let uploadedTempTargetsDatabase = "upload/uploaded-temptargets_database.json"
        static let uploadedMealPresets = "upload/uploaded-meal-presets.json"
        static let uploadedOverridePresets = "upload/uploaded-override-presets.json"
    }

    enum HealthKit {
        static let syncedGlucose = "healthkit/synced-glucose.json"
        static let syncedCarbs = "healthkit/synced-carbs.json"
        static let syncedInsulin = "healthkit/synced-insulin.json"
    }

    enum FreeAPS {
        static let settings = "freeaps/freeaps_settings.json"
        static let announcements = "freeaps/announcements.json"
        static let announcementsEnacted = "freeaps/announcements_enacted.json"
        static let tempTargetsPresets = "freeaps/temptargets_presets.json"
        static let calibrations = "freeaps/calibrations.json"
    }
}
