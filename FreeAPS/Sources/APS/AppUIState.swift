import Combine
import Foundation
import Observation

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
    private(set) var bolusInProgress: Bool = false
    private(set) var alertNotAck: Bool = false
    private(set) var lastLoopError: (error: String, date: Date)?
    private(set) var latestIOB: Decimal?
    private(set) var glucoseAlarm: GlucoseAlarm?

    private(set) var lightMode = LightMode.auto
    private(set) var liveActivitiesSystemEnabled: Bool = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }

    private var started = false
    func start() async {
        guard !started else { return }
        started = true
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
        bind(appCoordinator.bolusInProgress, to: \.bolusInProgress)
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
        subject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?[keyPath: keyPath] = value }
            }
            .store(in: &cancellables)
    }
}
