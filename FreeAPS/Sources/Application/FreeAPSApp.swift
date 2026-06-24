import ActivityKit
import CoreData
import Foundation
import SwiftUI
import Swinject

@main struct FreeAPSApp: App {
    @Environment(\.scenePhase) var scenePhase

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var dataController = CoreDataStack.shared

    // Dependencies Assembler
    // contain all dependencies Assemblies
    // TODO: Remove static key after update "Use Dependencies" logic
    private static let assembler = Assembler([
        StorageAssembly(),
        ServiceAssembly(),
        APSAssembly(),
        NetworkAssembly(),
        UIAssembly(),
        SecurityAssembly()
    ], parent: nil, defaultObjectScope: .container)

    // Temp static var
    // Use to backward compatibility with old Dependencies logic on Logger
    // TODO: Remove var after update "Use Dependencies" logic in Logger
    static let resolver: Resolver = FreeAPSApp.assembler.resolver

    private let appServices = AppServices(resolver: Self.resolver)

    private let appUIState = Self.resolver.resolve(AppUIState.self)!

    init() {
        debug(
            .default,
            "iAPS Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(Bundle.main.buildDate)] [buildExpires: \(Bundle.main.profileExpiration ?? "")]"
        )
        isNewVersion()
        AppearanceManager.setupGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            StartupGate(start: appServices.started) {
                Main.RootView(resolver: FreeAPSApp.resolver)
                    .environment(\.managedObjectContext, dataController.persistentContainer.viewContext)
                    .environmentObject(Icons())
                    .environment(appUIState)
                    .onOpenURL(perform: handleURL)
            }
        }
        .onChange(of: scenePhase) {
            debug(.default, "APPLICATION PHASE: \(scenePhase)")
            if scenePhase == .active {
                // device data manager subscribes to this subject and updates pump manager's BLE heartbeat preference
                appServices.appCoordinator?.sendAppBecomeActiveEvent()
            }
        }
    }

    private func handleURL(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch components?.host {
        case "device-select-resp":
            FreeAPSApp.resolver.resolve(NotificationCenter.self)!.post(name: .openFromGarminConnect, object: url)
        default: break
        }
    }

    private func isNewVersion() {
        let userDefaults = UserDefaults.standard
        var version = userDefaults.string(forKey: IAPSconfig.version) ?? ""
        userDefaults.set(false, forKey: IAPSconfig.inBolusView)

        guard version.count > 1, version == (Bundle.main.releaseVersionNumber ?? "") else {
            version = Bundle.main.releaseVersionNumber ?? ""
            userDefaults.set(version, forKey: IAPSconfig.version)
            userDefaults.set(true, forKey: IAPSconfig.newVersion)
            debug(.default, "Running new version: \(version)")
            return
        }
    }
}

private struct StartupGate<Content: View>: View {
    let start: () async throws -> Void
    @ViewBuilder var content: () -> Content

    @State private var ready = false
    @State private var error: String?

    var body: some View {
        ZStack {
            if let error {
                ZStack {
                    Text(error)
                }
            } else if ready {
                content()
            } else {
                LaunchPlaceholder()
            }
        }
        .task {
            do {
                try await start()
                ready = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct LaunchPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    private let logoSize: CGFloat = 116

    private var selectedIconPreview: String {
        let icon = UIApplication.shared.alternateIconName.flatMap(Icon_.init(rawValue:)) ?? .primary
        return icon.preview
    }

    var body: some View {
        ZStack {
            (colorScheme == .light ? IAPSconfig.homeViewBackgroundLight : IAPSconfig.homeViewBackgrundDark)
                .ignoresSafeArea()

            Image(selectedIconPreview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous))
                .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 10)
        }
    }
}
