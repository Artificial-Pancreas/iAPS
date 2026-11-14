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

    private let dataMigrations: DataMigrations

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
        // the instance AppServices starts (container scope): its downgrade warning is shown by StartupGate
        dataMigrations = Self.resolver.resolve(DataMigrations.self)!
        debug(
            .default,
            "iAPS Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(Bundle.main.buildDate.map { "\($0)" } ?? "unknown")] [buildExpires: \(Bundle.main.profileExpiration ?? "")]"
        )
        AppearanceManager.setupGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            StartupGate(start: appServices.started, dataMigrations: dataMigrations) {
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
    /// The start waits inside it while a downgrade warning is shown (`DataMigrations.downgradeWarning`).
    let dataMigrations: DataMigrations
    @ViewBuilder var content: () -> Content

    @State private var ready = false
    @State private var error: String?

    var body: some View {
        ZStack {
            if let error {
                ZStack {
                    Text(error)
                        .padding()
                }
            } else if let records = dataMigrations.downgradeWarning {
                // nothing else has started: the start goes on when the user acknowledges
                DataDowngradeWarningView(records: records) {
                    dataMigrations.acknowledgeDowngrade()
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

/// Shown instead of the app when its data was last used by a newer version (records of migrations this build does not
/// have, all of them downgradable). The texts of the migrations are the ones the newer version stored.
private struct DataDowngradeWarningView: View {
    let records: [DataMigrationRecord]
    let acknowledge: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString(
                    "Data from a newer version",
                    comment: "Downgrade warning at app start: title"
                ))
                    .font(.title2.bold())
                Text(NSLocalizedString(
                    "The data of this app was last used by a newer version of iAPS. That version made the changes listed below, which this version does not know about. Settings may differ from what you expect: check them before relying on the app.",
                    comment: "Downgrade warning at app start: explanation above the list of data changes"
                ))
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.description)
                            .font(.headline)
                        if let downgradeInfo = record.downgradeInfo, !downgradeInfo.isEmpty {
                            Text(downgradeInfo)
                        }
                        Text(String(
                            format: NSLocalizedString(
                                "Applied %1$@ by version %2$@",
                                comment: "Downgrade warning at app start: when a data change was made (1: date and time) and by which app version (2)"
                            ),
                            record.appliedAt.formatted(date: .abbreviated, time: .shortened),
                            record.appVersion
                        ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(NSLocalizedString(
                    "Nothing has been changed yet. When you continue, this version forgets these changes; they are made again when iAPS is next updated.",
                    comment: "Downgrade warning at app start: what the continue button does"
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: acknowledge) {
                Text(NSLocalizedString(
                    "I understand, continue to the app",
                    comment: "Downgrade warning at app start: the button that continues the start"
                ))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
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
