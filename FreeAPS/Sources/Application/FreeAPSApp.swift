import ActivityKit
import CoreData
import Foundation
import SwiftUI
import Swinject

@main struct FreeAPSApp: App {
    @Environment(\.scenePhase) var scenePhase

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var dataController: CoreDataStack

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

    private let appServices: AppServices

    private let appUIState: AppUIState

    init() {
        // Crash handlers first, so a crash anywhere in startup is captured - this is why the
        // dependency container and the Core Data stack are only built below. On a launch
        // before the first unlock after a reboot this is a no-op (the app cannot open its
        // files yet) and CrashReportService installs them once it can, when started by
        // AppServices. Whether a report ever leaves the phone is decided later, from the
        // Sharing setting.
        CrashReportService.install()
        _dataController = StateObject(wrappedValue: CoreDataStack.shared)
        appServices = Self.resolver.resolve(AppServices.self)!
        appUIState = Self.resolver.resolve(AppUIState.self)!
        debug(
            .default,
            "iAPS Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(Bundle.main.buildDate)] [buildExpires: \(Bundle.main.profileExpiration ?? "")]"
        )
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
            FootprintLog.log("app \(scenePhase)")
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

    fileprivate static func runVersionCheckOnce() {
        guard !didRunVersionCheck else { return }
        didRunVersionCheck = true
        isNewVersion()
    }

    private static var didRunVersionCheck = false

    private static func isNewVersion() {
        let userDefaults = UserDefaults.standard
        var version = userDefaults.string(forKey: IAPSconfig.version) ?? ""
        userDefaults.set(false, forKey: IAPSconfig.inBolusView)

        // Existing users who have never been shown the crash-report option get the Sharing
        // step once more (after the upgrade notice, if there is one). Deliberately not tied
        // to the version check below: dev keeps one marketing version for months, so most
        // users receive this feature without the version number moving.
        if version.count > 1, !userDefaults.bool(forKey: IAPSconfig.hasSeenCrashReportOption) {
            userDefaults.set(false, forKey: IAPSconfig.hasSeenSharingSetup)
        }

        guard version.count > 1, version == (Bundle.main.releaseVersionNumber ?? "") else {
            let hadPriorVersion = version.count > 1 // distinguishes an upgrade from a fresh install
            version = Bundle.main.releaseVersionNumber ?? ""
            userDefaults.set(version, forKey: IAPSconfig.version)
            userDefaults.set(true, forKey: IAPSconfig.newVersion)
            // Real upgrades get the "review your settings" notice (UpgradeNoticeView). Fresh
            // installs go through WelcomeView instead, so don't flag them here.
            if hadPriorVersion {
                userDefaults.set(true, forKey: IAPSconfig.showUpgradeNotice)
                // An upgrade is definitively an existing user, so skip the New-vs-Existing
                // WelcomeView (its flag is new this version and would otherwise read false
                // and pre-empt the upgrade notice). Fresh installs leave this false → Welcome.
                userDefaults.set(true, forKey: IAPSconfig.hasSeenWelcome)
            }
            if !hadPriorVersion {
                // A fresh install is offered crash reporting by its own setup flow (or chose
                // Skip on Welcome); the one-time re-show above is only for users who predate it.
                userDefaults.set(true, forKey: IAPSconfig.hasSeenCrashReportOption)
            }
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
                FreeAPSApp.runVersionCheckOnce()
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
