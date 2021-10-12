import SwiftUI
import Swinject

enum Screen: Identifiable, Hashable {
    case loading
    case home
    case settings
    case onboarding
    case authorizedRoot
    case login
    case requestPermissions
    case configEditor(file: String)
    case nighscoutConfig
    case pumpConfig
    case pumpSettingsEditor
    case basalProfileEditor
    case isfEditor
    case crEditor
    case targetsEditor
    case preferencesEditor
    case addCarbs
    case addTempTarget
    case bolus(waitForDuggestion: Bool)
    case manualTempBasal
    case autotuneConfig
    case dataTable
    case cgm

    var id: Int { String(reflecting: self).hashValue }
}

extension Screen {
    func view(resolver: Resolver) -> AnyView {
        switch self {
        case .loading:
            return ProgressView().asAny()
        case .home:
            return Home.Builder(resolver: resolver).buildView()
        case .settings:
            return Settings.Builder(resolver: resolver).buildView()
        case .onboarding:
            return Onboarding.Builder(resolver: resolver).buildView()
        case .authorizedRoot:
            return AuthorizedRoot.Builder(resolver: resolver).buildView()
        case .login:
            return Login.Builder(resolver: resolver).buildView()
        case .requestPermissions:
            return RequestPermissions.Builder(resolver: resolver).buildView()
        case let .configEditor(file):
            return ConfigEditor.Builder(resolver: resolver, file: file).buildView()
        case .nighscoutConfig:
            return NightscoutConfig.Builder(resolver: resolver).buildView()
        case .pumpConfig:
            return PumpConfig.Builder(resolver: resolver).buildView()
        case .pumpSettingsEditor:
            return PumpSettingsEditor.Builder(resolver: resolver).buildView()
        case .basalProfileEditor:
            return BasalProfileEditor.Builder(resolver: resolver).buildView()
        case .isfEditor:
            return ISFEditor.Builder(resolver: resolver).buildView()
        case .crEditor:
            return CREditor.Builder(resolver: resolver).buildView()
        case .targetsEditor:
            return TargetsEditor.Builder(resolver: resolver).buildView()
        case .preferencesEditor:
            return PreferencesEditor.Builder(resolver: resolver).buildView()
        case .addCarbs:
            return AddCarbs.Builder(resolver: resolver).buildView()
        case .addTempTarget:
            return AddTempTarget.Builder(resolver: resolver).buildView()
        case let .bolus(waitForSuggestion):
            return Bolus.Builder(resolver: resolver, waitForSuggestion: waitForSuggestion).buildView()
        case .manualTempBasal:
            return ManualTempBasal.Builder(resolver: resolver).buildView()
        case .autotuneConfig:
            return AutotuneConfig.Builder(resolver: resolver).buildView()
        case .dataTable:
            return DataTable.Builder(resolver: resolver).buildView()
        case .cgm:
            return CGM.Builder(resolver: resolver).buildView()
        }
    }

    func modal(resolver: Resolver) -> Main.Modal {
        .init(screen: self, view: view(resolver: resolver))
    }
}
