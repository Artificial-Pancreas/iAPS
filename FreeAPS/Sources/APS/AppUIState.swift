import Combine
import Foundation
import Observation
import UIKit

@MainActor
@Observable final class AppUIState: AppService {
    private let appCoordinator: AppCoordinator

    // initial values will not be observed by tha app, SettingsManager sets the real values in its start(), and the app won't render before it's finished
    private(set) var settings = FreeAPSSettings()
    private(set) var preferences = Preferences()
    private(set) var pumpSettings = PumpSettings.defaultValue

    private(set) var pumpInfo: PumpDisplayInfo?
    private(set) var pumpStatus: PumpDisplayStatus?
    private(set) var cgmInfo: CgmDisplayInfo?
    private(set) var cgmStatus: CgmDisplayStatus?
    private(set) var isLooping = false
    private(set) var manualTempBasal = false
    private(set) var pumpReservoir: ReservoirReading?
    private(set) var lastLoopDate: Date?
    private(set) var bolusProgress: Decimal?
    private(set) var bolusAmount: Decimal?
    private(set) var alertNotAck: Bool = false
    private(set) var lastLoopError: (error: String, date: Date)?
    private(set) var latestIOB: Decimal?
    private(set) var glucoseAlarm: GlucoseAlarm?

    private(set) var lightMode = LightMode.auto
    private(set) var liveActivitiesSystemEnabled: Bool = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // While the app is in the background there is no UI to keep current, so observable
    // writes are deferred (latest value per property wins) and flushed on foregrounding.
    // Otherwise every bus emission would keep re-evaluating the invisible view tree.
    @ObservationIgnored private var isInBackground = false
    @ObservationIgnored private var pendingWrites: [AnyKeyPath: () -> Void] = [:]

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }

    private var started = false
    func start() async {
        guard !started else { return }
        started = true

        isInBackground = UIApplication.shared.applicationState == .background
        Foundation.NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.isInBackground = true }
            }
            .store(in: &cancellables)
        Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.flushPendingWrites() }
            }
            .store(in: &cancellables)

        settings = appCoordinator.settings.value
        preferences = appCoordinator.preferences.value
        pumpSettings = appCoordinator.pumpSettings.value
        lightMode = appCoordinator.settings.value.lightMode

        bind(appCoordinator.settings, to: \.settings)
        bind(appCoordinator.preferences, to: \.preferences)
        bind(appCoordinator.pumpSettings, to: \.pumpSettings)

        bind(appCoordinator.pumpInfo, to: \.pumpInfo)
        bind(appCoordinator.pumpStatus, to: \.pumpStatus)
        bind(appCoordinator.cgmInfo, to: \.cgmInfo)
        bind(appCoordinator.cgmStatus, to: \.cgmStatus)
        bind(appCoordinator.isLooping, to: \.isLooping)
        bind(appCoordinator.manualTempBasal, to: \.manualTempBasal)
        bind(appCoordinator.pumpStatus.map(\.?.reservoir), to: \.pumpReservoir)
        bind(appCoordinator.lastLoopDate, to: \.lastLoopDate)
        bind(appCoordinator.bolusProgress, to: \.bolusProgress)
        bind(appCoordinator.bolusAmount, to: \.bolusAmount)
        bind(appCoordinator.lastLoopError, to: \.lastLoopError)
        bind(appCoordinator.alertNotAckUpdates, to: \.alertNotAck)
        bind(appCoordinator.glucoseAlarm, to: \.glucoseAlarm)
        bind(appCoordinator.liveActivitiesSystemEnabled, to: \.liveActivitiesSystemEnabled)
        bind(appCoordinator.settings.map(\.lightMode).removeDuplicates(), to: \.lightMode)
        bind(appCoordinator.iobTicks.map(\.?.first?.iob).removeDuplicates(), to: \.latestIOB)
    }

    private func bind<V>(
        _ subject: some Publisher<V, Never>,
        to keyPath: ReferenceWritableKeyPath<AppUIState, V>
    ) {
        subscribe(subject, to: keyPath)
    }

    private func bind<V: Equatable>(
        _ subject: some Publisher<V, Never>,
        to keyPath: ReferenceWritableKeyPath<AppUIState, V>
    ) {
        subscribe(subject.removeDuplicates(), to: keyPath)
    }

    private func subscribe<V>(
        _ subject: some Publisher<V, Never>,
        to keyPath: ReferenceWritableKeyPath<AppUIState, V>
    ) {
        subject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.write(value, to: keyPath) }
            }
            .store(in: &cancellables)
    }

    private func write<V>(_ value: V, to keyPath: ReferenceWritableKeyPath<AppUIState, V>) {
        if isInBackground {
            pendingWrites[keyPath] = { [weak self] in self?[keyPath: keyPath] = value }
        } else {
            self[keyPath: keyPath] = value
        }
    }

    private func flushPendingWrites() {
        isInBackground = false
        let writes = pendingWrites
        pendingWrites = [:]
        writes.values.forEach { $0() }
    }
}
