import Foundation

struct SettingsSearchEntry: Identifiable {
    let id = UUID()
    let name: String
    let section: String
    let destination: Screen
}

enum SettingsCatalogue {
    static let entries: [SettingsSearchEntry] =
        devices + services + configuration + openAPSMain + openAPSSMB + openAPSTargets + openAPSOther +
        autotuneSettings + autoISFToggles + autoISFNighttime + autoISFSettings + autoISFB30 + autoISFKeto +
        dynamicISF + bolusCalculator + fpuConversion + uiuxSettings
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
    .init(name: "Calculate ISF Suggestions", section: "Autotune", destination: .autotuneConfig),
    .init(name: "ISF Scale", section: "Autotune", destination: .autotuneConfig),
    .init(name: "Calculated Basal", section: "Autotune", destination: .autotuneConfig),
    .init(name: "Calculated ISF", section: "Autotune", destination: .autotuneConfig),
]

// MARK: - Auto ISF

private let autoISFToggles: [SettingsSearchEntry] = [
    .init(name: "Enable Auto ISF", section: "Auto ISF", destination: .autoISF),
    .init(name: "Enable BG Acceleration", section: "Auto ISF", destination: .autoISF),
    .init(name: "Enable Auto CR", section: "Auto ISF", destination: .autoISF),
]

private let autoISFNighttime: [SettingsSearchEntry] = [
    .init(name: "Disable Auto ISF During Nighttime", section: "Auto ISF", destination: .autoISF),
]

private let autoISFSettings: [SettingsSearchEntry] = [
    .init(name: "Auto ISF Max", section: "Auto ISF", destination: .autoISF),
    .init(name: "Auto ISF Min", section: "Auto ISF", destination: .autoISF),
    .init(name: "SMB Delivery Ratio Minimum", section: "Auto ISF", destination: .autoISF),
    .init(name: "SMB Delivery Ratio Maximum", section: "Auto ISF", destination: .autoISF),
    .init(name: "SMB Delivery Ratio BG Range", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF Weight for Higher BG", section: "Auto ISF", destination: .autoISF),
    .init(name: "Duration Weight", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF Weight for Lower BG", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF Weight for Postprandial BG Rise", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF Weight While BG Accelerates", section: "Auto ISF", destination: .autoISF),
    .init(name: "ISF Weight While BG Decelerates", section: "Auto ISF", destination: .autoISF),
    .init(name: "Max IOB Threshold Percent", section: "Auto ISF", destination: .autoISF),
]

private let autoISFB30: [SettingsSearchEntry] = [
    .init(name: "Activate B30", section: "Auto ISF", destination: .autoISF),
    .init(name: "Minimum Start Bolus Size", section: "Auto ISF", destination: .autoISF),
    .init(name: "Target Level for B30", section: "Auto ISF", destination: .autoISF),
    .init(name: "B30 Upper BG Limit", section: "Auto ISF", destination: .autoISF),
    .init(name: "B30 Upper Delta Limit", section: "Auto ISF", destination: .autoISF),
    .init(name: "B30 Basal Rate Increase Factor", section: "Auto ISF", destination: .autoISF),
    .init(name: "Duration of Increased B30 Basal Rate", section: "Auto ISF", destination: .autoISF),
]

private let autoISFKeto: [SettingsSearchEntry] = [
    .init(name: "Enable Keto Protection", section: "Auto ISF", destination: .autoISF),
    .init(name: "Variable Keto Protection", section: "Auto ISF", destination: .autoISF),
    .init(name: "Keto Protection Safety TBR %", section: "Auto ISF", destination: .autoISF),
    .init(name: "Enable Keto Protection With Pre-Defined TBR", section: "Auto ISF", destination: .autoISF),
    .init(name: "Absolute Safety TBR", section: "Auto ISF", destination: .autoISF),
]

// MARK: - Dynamic ISF

private let dynamicISF: [SettingsSearchEntry] = [
    .init(name: "Activate Dynamic Sensitivity (ISF)", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Activate Dynamic Carb Ratio (CR)", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Use Sigmoid Function", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Adjustment Factor", section: "Dynamic ISF", destination: .dynamicISF),
    .init(name: "Weighted Average of TDD", section: "Dynamic ISF", destination: .dynamicISF),
]

// MARK: - Bolus Calculator

private let bolusCalculator: [SettingsSearchEntry] = [
    .init(name: "Use Bolus Calculator", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Bolus Calculator Override Factor", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Apply Factor for Fatty Meals", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Display Predictions", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
    .init(name: "Don't Use 15 Min Trend", section: "Bolus Calculator", destination: .bolusCalculatorConfig),
]

// MARK: - Fat and Protein Conversion

private let fpuConversion: [SettingsSearchEntry] = [
    .init(name: "FPU Delay In Minutes", section: "Fat & Protein", destination: .fpuConfig),
    .init(name: "FPU Maximum Duration In Hours", section: "Fat & Protein", destination: .fpuConfig),
    .init(name: "FPU Interval In Minutes", section: "Fat & Protein", destination: .fpuConfig),
    .init(name: "FPU Individual Adjustment Factor", section: "Fat & Protein", destination: .fpuConfig),
]

// MARK: - UI/UX

private let uiuxSettings: [SettingsSearchEntry] = [
    .init(name: "Display Temp Targets Button", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Profile Override Button", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Meal Button", section: "UI/UX", destination: .uiConfig),
    .init(name: "Never Display Small Glucose Chart", section: "UI/UX", destination: .uiConfig),
    .init(name: "Always Color Glucose Value", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Glucose Delta", section: "UI/UX", destination: .uiConfig),
    .init(name: "Hide Concentration Badge", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Sensor Age", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Sensor Time Remaining", section: "UI/UX", destination: .uiConfig),
    .init(name: "Override HbA1c Unit", section: "UI/UX", destination: .uiConfig),
    .init(name: "Standing / Laying TIR Chart", section: "UI/UX", destination: .uiConfig),
    .init(name: "Skip Bolus Screen After Carbs", section: "UI/UX", destination: .uiConfig),
    .init(name: "Display Fat and Protein Entries", section: "UI/UX", destination: .uiConfig),
    .init(name: "AI Food Search", section: "UI/UX", destination: .uiConfig),
    .init(name: "Color Scheme", section: "UI/UX", destination: .uiConfig),
    .init(name: "Main Chart Settings", section: "UI/UX", destination: .mainChartConfig),
]
