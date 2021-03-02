import SwiftUI
import Swinject

enum Screen: Identifiable {
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

    var id: Int { String(reflecting: self).hashValue }
}

extension Screen {
    func view(resolver: Resolver) -> AnyView {
        switch self {
        case .home:
            return Home.Builder(resolver: resolver).buildView()
        case .settings:
            return Settings.Builder(resolver: resolver).buildView()
        case .onboarding:
            return Onboarding.Builder(resolver: resolver).buildView()
        case .authorizedRoot:
            return AuthotizedRoot.Builder(resolver: resolver).buildView()
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
        }
    }

    func tab(resolver: Resolver) -> AuthotizedRoot.Tab {
        let tabView = view(resolver: resolver)
        switch self {
        case .home:
            return .init(
                rootScreen: self,
                view: tabView,
                image: Image(systemName: "house"),
                text: Text("Home")
            )
        case .settings:
            return .init(
                rootScreen: self,
                view: tabView,
                image: Image(systemName: "gear"),
                text: Text("Settings")
            )
        default:
            fatalError("Tab for this screen \(self) did not specified")
        }
    }

    func modal(resolver: Resolver) -> Main.Modal {
        .init(screen: self, view: view(resolver: resolver))
    }
}
