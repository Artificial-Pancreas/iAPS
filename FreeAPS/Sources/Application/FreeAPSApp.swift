import ActivityKit
import CoreData
import Foundation
import SwiftUI
import Swinject

@main struct FreeAPSApp: App {
    @Environment(\.scenePhase) var scenePhase

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var dataController = CoreDataStack.shared
    @StateObject private var crashReporter = CrashReportService()
    @State private var showCrashAlert = false

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

    // TODO: do we want this? will this work with the Router?
    // can be shared with the rest of the views with @EnvironmentObject
    @StateObject private var appServices = AppServices(assembler: assembler)

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
            Main.RootView(resolver: FreeAPSApp.resolver)
                .environment(\.managedObjectContext, dataController.persistentContainer.viewContext)
                .environmentObject(Icons())
                .onOpenURL(perform: handleURL)
                .environmentObject(appServices)
                .alert("Crash Detected", isPresented: $showCrashAlert) {
                    Button("Upload Report") { crashReporter.uploadAndDismiss() }
                    Button("Skip", role: .cancel) { crashReporter.dismiss() }
                } message: {
                    Text(
                        "iAPS crashed during a previous session. Would you like to send a crash report to open-iaps.app to help diagnose the issue? No personal data is included."
                    )
                }
                .onChange(of: crashReporter.pendingCount) {
                    if crashReporter.pendingCount > 0 {
                        showCrashAlert = true
                    }
                }
        }
        .onChange(of: scenePhase) {
            debug(.default, "APPLICATION PHASE: \(scenePhase)")
            if scenePhase == .active {
                appServices.deviceManager.didBecomeActive()
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
