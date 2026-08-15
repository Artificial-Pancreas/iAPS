import ActivityKit
import CoreData
import Foundation
import SwiftUI
import Swinject
import UIKit

@main struct FreeAPSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Dependencies Assembler
    // contain all dependencies Assemblies
    // TODO: Remove static key after update "Use Dependencies" logic
    fileprivate static let assembler = Assembler([
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

    init() {
        debug(
            .default,
            "iAPS Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(Bundle.main.buildDate)] [buildExpires: \(Bundle.main.profileExpiration ?? "")]"
        )
        AppearanceManager.setupGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
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

        guard version.count > 1, version == (Bundle.main.releaseVersionNumber ?? "") else {
            version = Bundle.main.releaseVersionNumber ?? ""
            userDefaults.set(version, forKey: IAPSconfig.version)
            userDefaults.set(true, forKey: IAPSconfig.newVersion)
            debug(.default, "Running new version: \(version)")
            return
        }
    }
}

/// Holds the launch until the app can actually read its own files.
private struct LaunchGateView: View {
    @State private var isProtectedDataAvailable = ProtectedDataGate.isAvailable()

    var body: some View {
        Group {
            if isProtectedDataAvailable {
                LaunchedAppView()
            } else {
                WaitingForUnlockView()
            }
        }
        .onAppear {
            if !isProtectedDataAvailable {
                debug(.default, "Launch deferred: protected data is not available (no unlock since boot)")
            }
        }
        .onReceive(
            Foundation.NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
        ) { _ in
            resumeLaunchIfPossible()
        }
        .onReceive(
            Foundation.NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            resumeLaunchIfPossible()
        }
    }

    private func resumeLaunchIfPossible() {
        guard !isProtectedDataAvailable, ProtectedDataGate.isAvailable() else { return }
        debug(.default, "Protected data became available, resuming launch")
        isProtectedDataAvailable = true
    }
}

/// The real app - reached only once `ProtectedDataGate` confirms our files are readable.
private struct LaunchedAppView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var dataController = CoreDataStack.shared
    @StateObject private var appServices = AppServices(assembler: FreeAPSApp.assembler)

    init() {
        FreeAPSApp.runVersionCheckOnce()
    }

    var body: some View {
        Main.RootView(resolver: FreeAPSApp.resolver)
            .environment(\.managedObjectContext, dataController.persistentContainer.viewContext)
            .environmentObject(Icons())
            .onOpenURL(perform: handleURL)
            .environmentObject(appServices)
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
}

private struct WaitingForUnlockView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Starting iAPS")
                .font(.headline)
            Text(
                "iAPS is waiting for access to its data. Normally this finishes on its own once you have unlocked your phone for the first time after a restart."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }
}

enum ProtectedDataGate {
    private static let probeName = "protection.test"

    private static var didBecomeAvailable = false

    static func isAvailable() -> Bool {
        if didBecomeAvailable {
            return true
        }
        didBecomeAvailable = probe()
        return didBecomeAvailable
    }

    private static func probe() -> Bool {
        let fileManager = FileManager.default
        guard let documents = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return false
        }

        let probeURL = documents.appendingPathComponent(probeName)

        if !fileManager.fileExists(atPath: probeURL.path) {
            try? Data("iAPS".utf8).write(to: probeURL, options: .completeFileProtectionUntilFirstUserAuthentication)
        }

        return (try? Data(contentsOf: probeURL)) != nil
    }
}
