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

    var id: Int { String(reflecting: self).hashValue }
}

struct UseCustomBackGround: ViewModifier {
    let test = LinearGradientBackGround()
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(test).ignoresSafeArea()
    }
}

extension View {
    func useCustomBackGround() -> some View {
        modifier(UseCustomBackGround())
    }
}

struct UseCustomBackGroundForPumpManagers: ViewModifier {
    let test = LinearGradientBackGround()
    func body(content: Content) -> some View {
        content
            .background(test).ignoresSafeArea()
    }
}

extension View {
    func useCustomBackGroundForPumpManagers() -> some View {
        modifier(UseCustomBackGround())
    }
}

extension Screen {
    @ViewBuilder func view(resolver: Resolver) -> some View {
        switch self {
        case .loading:
            ProgressView()
        case .home:
            Home.RootView(resolver: resolver)
                .useCustomBackGround()
        case .settings:
            Settings.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case let .configEditor(file):
            ConfigEditor.RootView(resolver: resolver, file: file)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .nighscoutConfig:
            NightscoutConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .pumpConfig:
            PumpConfig.RootView(resolver: resolver)
        case .pumpSettingsEditor:
            PumpSettingsEditor.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .basalProfileEditor:
            BasalProfileEditor.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .isfEditor:
            ISFEditor.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .crEditor:
            CREditor.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .targetsEditor:
            TargetsEditor.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .preferencesEditor:
            PreferencesEditor.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case let .addCarbs(editMode, override):
            AddCarbs.RootView(resolver: resolver, editMode: editMode, override: override)
                .padding(.top, IAPSconfig.padding - 30)
                .useCustomBackGround()
        case .addTempTarget:
            AddTempTarget.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case let .bolus(waitForSuggestion, fetch):
            Bolus.RootView(resolver: resolver, waitForSuggestion: waitForSuggestion, fetch: fetch)
                .padding(.top, IAPSconfig.padding - 30)
                .useCustomBackGround()
        case .manualTempBasal:
            ManualTempBasal.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .autotuneConfig:
            AutotuneConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .dataTable:
            DataTable.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .cgm:
            CGM.RootView(resolver: resolver)
        case .healthkit:
            AppleHealthKit.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .libreConfig:
            LibreConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .calibrations:
            Calibrations.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .notificationsConfig:
            NotificationsConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .fpuConfig:
            FPUConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .iconConfig:
            IconConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .overrideProfilesConfig:
            OverrideProfilesConfig.RootView(resolver: resolver)
        case .snooze:
            Snooze.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .watch:
            WatchConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .statistics:
            Stat.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .statisticsConfig:
            StatConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .bolusCalculatorConfig:
            BolusCalculatorConfig.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        case .dynamicISF:
            Dynamic.RootView(resolver: resolver)
                .padding(.top, IAPSconfig.padding)
                .useCustomBackGround()
        }
    }

    func modal(resolver: Resolver) -> Main.Modal {
        .init(screen: self, view: view(resolver: resolver).asAny())
    }
}
