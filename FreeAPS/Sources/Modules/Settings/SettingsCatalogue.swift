import Foundation

/// One searchable setting. `name` and `section` are the labels exactly as the screens show
/// them, which makes them the localization keys too: the search matches and displays the
/// user's language, with the English key as a fallback so English terms keep working.
struct SettingsSearchEntry: Identifiable {
    let id = UUID()
    let name: String
    let section: String
    let destination: Screen

    var localizedName: String {
        NSLocalizedString(name, comment: "").trimmingCharacters(in: .whitespaces)
    }

    var localizedSection: String {
        NSLocalizedString(section, comment: "")
    }

    /// Case- and diacritic-insensitive ("ziel" finds "Zielwert", "senal" finds "señal").
    func matches(_ query: String) -> Bool {
        [localizedName, name, localizedSection, section].contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

enum SettingsCatalogue {
    static let entries: [SettingsSearchEntry] =
        devices + services + configuration + openAPSMain + openAPSSMB + openAPSTargets + openAPSOther +
        autotuneSettings + autoISFToggles + autoISFNighttime + autoISFSettings + autoISFB30 + autoISFKeto +
        dynamicISF + bolusCalculator + fpuConversion + uiuxSettings + mainChart
}

// MARK: - Devices

private let devices: [SettingsSearchEntry] = [
    .init(name: "Pump", section: "Devices", destination: .pumpConfig),
    .init(name: "CGM", section: "Devices", destination: .cgm),
    .init(name: "Watch", section: "Devices", destination: .watch),
]

// MARK: - Services

private let services: [SettingsSearchEntry] = [
    .init(name: "Nightscout", section: "Services", destination: .nighscoutConfig),
    .init(name: "Apple Health", section: "Services", destination: .healthkit),
    .init(name: "Notifications", section: "Services", destination: .notificationsConfig),
]

// MARK: - Configuration

private let configuration: [SettingsSearchEntry] = [
    .init(name: "Pump Settings", section: "Configuration", destination: .pumpSettingsEditor),
    .init(name: "Basal Profile", section: "Configuration", destination: .basalProfileEditor(saveNewConcentration: false)),
    .init(name: "Insulin Sensitivities", section: "Configuration", destination: .isfEditor),
    .init(name: "Carb Ratios", section: "Configuration", destination: .crEditor),
    .init(name: "Target Glucose", section: "Configuration", destination: .targetsEditor),
]

// MARK: - OpenAPS

private let openAPSMain: [SettingsSearchEntry] = [
    .init(name: "Max IOB", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Max COB", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Max Daily Safety Multiplier", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Current Basal Safety Multiplier", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Threshold Setting", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Autosens Maximum", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Autosens Minimum", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Autotune ISF Adjustment Fraction", section: "OpenAPS", destination: .preferencesEditor),
]

private let openAPSSMB: [SettingsSearchEntry] = [
    .init(name: "Enable SMB Always", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Max Delta-BG Threshold SMB", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Enable SMB With COB", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Enable SMB With Temptarget", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Enable SMB After Carbs", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Allow SMB With High Temptarget", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Enable SMB With High BG", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Enable UAM", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Max SMB Basal Minutes", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Max UAM SMB Basal Minutes", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "SMB DeliveryRatio", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "SMB Interval", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Bolus Increment", section: "OpenAPS", destination: .preferencesEditor),
]

private let openAPSTargets: [SettingsSearchEntry] = [
    .init(name: "Sensitivity Raises Target", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Resistance Lowers Target", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "High Temptarget Raises Sensitivity", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Low Temptarget Lowers Sensitivity", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Half Basal Exercise Target", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Rewind Resets Autosens", section: "OpenAPS", destination: .preferencesEditor),
]

private let openAPSOther: [SettingsSearchEntry] = [
    .init(name: "Use Custom Peak Time", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Insulin Peak Time", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Skip Neutral Temps", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Unsuspend If No Temp", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Suspend Zeros IOB", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Min 5m Carbimpact", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Remaining Carbs Fraction", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Remaining Carbs Cap", section: "OpenAPS", destination: .preferencesEditor),
    .init(name: "Noisy CGM Target Multiplier", section: "OpenAPS", destination: .preferencesEditor),
]

// MARK: - Autotune

private let autotuneSettings: [SettingsSearchEntry] = [
    .init(name: "Use Autotune", section: "Autotune", destination: .autotuneConfig),
    .init(name: "Only Autotune Basal Insulin", section: "Autotune", destination: .autotuneConfig),
    .init(name: "Save on Pump", section: "Autotune", destination: .autotuneConfig),
    .init(name: "Delete autotune data", section: "Autotune", destination: .autotuneConfig),
]

// MARK: - Auto ISF

private let autoISFToggles: [SettingsSearchEntry] = [
    .init(name: "Enable Auto ISF", section: "Auto ISF", destination: .autoISF),
    .init(name: "Enable BG acceleration", section: "Auto ISF", destination: .autoISF),
    .init(name: "Enable Auto CR", section: "Auto ISF", destination: .autoISF),
]

private let autoISFNighttime: [SettingsSearchEntry] = [
    .init(name: "Disable during nighttime", section: "Auto ISF", destination: .autoISF),
]

private let autoISFSettings: [SettingsSearchEntry] = [
    .init(name: "Auto ISF Max", section: "Auto ISF", destination: .autoISF),
    .init(name: "Auto ISF Min", section: "Auto ISF", destination: .autoISF),
    .init(name: "SMB Delivery Ratio Minimum", section: "Auto ISF", destination: .autoISF),
    .init(name: "SMB Delivery Ratio Maximum", section: "Auto ISF", destination: .autoISF),
    .init(name: "SMB Delivery Ratio BG Range", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF weight for higher BG", section: "Auto ISF", destination: .autoISF),
    .init(name: "Duration Weight", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF weight for lower BG", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF weight for postprandial BG rise", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF weight while BG accelerates", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF weight while BG decelerates", section: "Auto ISF", destination: .autoISF),
    .init(name: "Max IOB Threshold Percent", section: "Auto ISF", destination: .autoISF),
]

private let autoISFB30: [SettingsSearchEntry] = [
    .init(name: "Activate B30", section: "Auto ISF", destination: .autoISF),
    .init(name: "Minimum Start Bolus size", section: "Auto ISF", destination: .autoISF),
    .init(name: "Target Level for B30 to be enacted", section: "Auto ISF", destination: .autoISF),
    .init(name: "Upper BG limit", section: "Auto ISF", destination: .autoISF),
    .init(name: "Upper Delta limit", section: "Auto ISF", destination: .autoISF),
    .init(name: "B30 Basal rate increase factor", section: "Auto ISF", destination: .autoISF),
    .init(name: "Duration of increased B30 basal rate", section: "Auto ISF", destination: .autoISF),
]

private let autoISFKeto: [SettingsSearchEntry] = [
    .init(name: "Enable Keto Protection", section: "Auto ISF", destination: .autoISF),
    .init(name: "Variable Keto Protection", section: "Auto ISF", destination: .autoISF),
    .init(name: "Safety TBR in %", section: "Auto ISF", destination: .autoISF),
    .init(name: "Enable Keto protection with pre-defined TBR", section: "Auto ISF", destination: .autoISF),
    .init(name: "Absolute Safety TBR", section: "Auto ISF", destination: .autoISF),
]

// MARK: - Dynamic ISF

private let dynamicISF: [SettingsSearchEntry] = [
    .init(name: "Activate Dynamic Sensitivity (ISF)", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Activate Dynamic Carb Ratio (CR)", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Use Sigmoid Function", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Adjustment Factor", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Weighted Average of TDD. Weight of past 24 hours:", section: "Dynamic ISF", destination: .dynamicISF),
]

// MARK: - Bolus Calculator

private let bolusCalculator: [SettingsSearchEntry] = [
    .init(name: "Use Bolus Calculator", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Override With A Factor Of ", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Apply factor for fatty meals", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Display Predictions", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Don't Use 15 min Trend", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Allow iOS Bolus Shortcuts", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
]

// MARK: - Fat and Protein Conversion

private let fpuConversion: [SettingsSearchEntry] = [
    .init(name: "Delay In Minutes", section: "Fat And Protein Conversion", destination: .fpuConfig),
    .init(name: "Maximum Duration In Hours", section: "Fat And Protein Conversion", destination: .fpuConfig),
    .init(name: "Interval In Minutes", section: "Fat And Protein Conversion", destination: .fpuConfig),
    .init(name: "Override With A Factor Of ", section: "Fat And Protein Conversion", destination: .fpuConfig),
]

// MARK: - UI/UX

private let uiuxSettings: [SettingsSearchEntry] = [
    .init(name: "Display Temp Targets Button", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Profile Override Button", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Meal Button", section: "UI/UX", destination: .uiConfig),
    .init(name: "Never display the small glucose chart when scrolling", section: "UI/UX", destination: .uiConfig),
    .init(name: "Always Color Glucose Value (green, yellow etc)", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Glucose Delta", section: "UI/UX", destination: .uiConfig),
    .init(name: "Hide Concentration Badge", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Sensor Age", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Sensor Time Remaining", section: "UI/UX", destination: .uiConfig),
    .init(name: "Override HbA1c Unit", section: "UI/UX", destination: .uiConfig),
    .init(name: "Standing / Laying TIR Chart", section: "UI/UX", destination: .uiConfig),
    .init(name: "Skip Bolus screen after carbs", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display and allow Fat and Protein entries", section: "UI/UX", destination: .uiConfig),
    .init(name: "AI Food Search", section: "UI/UX", destination: .uiConfig),
    .init(name: "Color Scheme", section: "UI/UX", destination: .uiConfig),
    .init(name: "Main Chart settings", section: "UI/UX", destination: .mainChartConfig),
]

// MARK: - Main Chart

private let mainChart: [SettingsSearchEntry] = [
    .init(name: "Hide Predictions", section: "Main Chart", destination: .mainChartConfig),
    .init(name: "Use carb bars", section: "Main Chart", destination: .mainChartConfig),
    .init(name: "Use insulin bars", section: "Main Chart", destination: .mainChartConfig),
    .init(name: "Horizontal Scroll View Visible hours", section: "Main Chart", destination: .mainChartConfig),
    .init(name: "Threshold lines (Low / High)", section: "Main Chart", destination: .mainChartConfig),
    .init(name: "Secondary chart", section: "Main Chart", destination: .mainChartConfig),
]
