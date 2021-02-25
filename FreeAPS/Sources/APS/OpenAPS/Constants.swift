extension OpenAPS {
    enum Bundle {
        static let iob = "bundle/iob"
        static let meal = "bundle/meal"
        static let autotunePrep = "bundle/autotune-prep"
        static let autotuneCore = "bundle/autotune-core"
        static let getLastGlucose = "bundle/glucose-get-last"
        static let basalSetTemp = "bundle/basal-set-temp"
        static let determineBasal = "bundle/determine-basal"
        static let autosens = "bundle/autosens"
        static let profile = "bundle/profile"
    }

    enum Prepare {
        static let iob = "prepare/iob"
        static let meal = "prepare/meal"
        static let autotunePrep = "prepare/autotune-prep"
        static let autotuneCore = "prepare/autotune-core"
        static let determineBasal = "prepare/determine-basal"
        static let autosens = "prepare/autosens"
        static let profile = "prepare/profile"
    }

    enum Settings {
        static let preferences = "preferences.json"
        static let autotune = "settings/autotune.json"
        static let autosense = "settings/autosense.json"
    }

    enum Monitor {
        static let pumpHistory = "monitor/pumphistory.json"
    }

    enum Function {
        static let freeaps = "freeaps"
        static let generate = "generate"
        static let tempBasalFunctions = "tempBasalFunctions"
        static let exportDefaults = "exportDefaults"
    }
}
