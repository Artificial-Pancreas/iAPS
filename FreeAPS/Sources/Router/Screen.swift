import Combine
import SwiftUI
import Swinject

enum Screen: Identifiable, Hashable {
    case loading
    case home
    case settings
    case configEditor(file: String)
    case nighscoutConfig
    case pumpConfig
    case pumpSettingsEditor
    case basalProfileEditor
    case isfEditor
    case crEditor
    case targetsEditor
    case preferencesEditor
    case addCarbs(editMode: Bool, override: Bool)
    case addTempTarget
    case bolus(waitForSuggestion: Bool, fetch: Bool)
    case manualTempBasal
    case autotuneConfig
    case dataTable
    case cgm
    case healthkit
    case libreConfig
    case calibrations
    case notificationsConfig
    case fpuConfig
    case iconConfig
    case overrideProfilesConfig
    case snooze
    case statistics
    case watch
    case statisticsConfig
    case bolusCalculatorConfig
    case dynamicISF
    case contactTrick
    case sharing
    var id: Int { String(reflecting: self).hashValue }
}

extension Screen {
    @ViewBuilder func view(resolver: Resolver) -> some View {
        switch self {
        case .loading:
            ProgressView()
        case .home:
            Home.RootView(resolver: resolver)
        case .settings:
            Settings.RootView(resolver: resolver)
        case let .configEditor(file):
            ConfigEditor.RootView(resolver: resolver, file: file)
        case .nighscoutConfig:
            NightscoutConfig.RootView(resolver: resolver)
        case .pumpConfig:
            PumpConfig.RootView(resolver: resolver)
        case .pumpSettingsEditor:
            PumpSettingsEditor.RootView(resolver: resolver)
        case .basalProfileEditor:
            BasalProfileEditor.RootView(resolver: resolver)
        case .isfEditor:
            ISFEditor.RootView(resolver: resolver)
        case .crEditor:
            CREditor.RootView(resolver: resolver)
        case .targetsEditor:
            TargetsEditor.RootView(resolver: resolver)
        case .preferencesEditor:
            PreferencesEditor.RootView(resolver: resolver)
        case let .addCarbs(editMode, override):
            AddCarbs.RootView(resolver: resolver, editMode: editMode, override: override)
        case .addTempTarget:
            AddTempTarget.RootView(resolver: resolver)
        case let .bolus(waitForSuggestion, fetch):
            Bolus.RootView(resolver: resolver, waitForSuggestion: waitForSuggestion, fetch: fetch)
        case .manualTempBasal:
            ManualTempBasal.RootView(resolver: resolver)
        case .autotuneConfig:
            AutotuneConfig.RootView(resolver: resolver)
        case .dataTable:
            DataTable.RootView(resolver: resolver)
        case .cgm:
            CGM.RootView(resolver: resolver)
        case .healthkit:
            AppleHealthKit.RootView(resolver: resolver)
        case .libreConfig:
            LibreConfig.RootView(resolver: resolver)
        case .calibrations:
            Calibrations.RootView(resolver: resolver)
        case .notificationsConfig:
            NotificationsConfig.RootView(resolver: resolver)
        case .fpuConfig:
            FPUConfig.RootView(resolver: resolver)
        case .iconConfig:
            IconConfig.RootView(resolver: resolver)
        case .overrideProfilesConfig:
            OverrideProfilesConfig.RootView(resolver: resolver)
        case .snooze:
            Snooze.RootView(resolver: resolver)
        case .watch:
            WatchConfig.RootView(resolver: resolver)
        case .statistics:
            Stat.RootView(resolver: resolver)
        case .statisticsConfig:
            StatConfig.RootView(resolver: resolver)
        case .bolusCalculatorConfig:
            BolusCalculatorConfig.RootView(resolver: resolver)
        case .dynamicISF:
            Dynamic.RootView(resolver: resolver)
        case .contactTrick:
            ContactTrick.RootView(resolver: resolver)
        case .sharing:
            Sharing.RootView(resolver: resolver)
        }
    }

    func modal(resolver: Resolver) -> Main.Modal {
        .init(screen: self, view: view(resolver: resolver).asAny())
    }
}
