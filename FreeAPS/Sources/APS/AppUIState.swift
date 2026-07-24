import Combine
import Foundation
import Observation

@MainActor
@Observable final class AppUIState: AppService, UIBindingOwner {
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
    private(set) var latestCOB: Decimal?
    private(set) var glucoseAlarm: GlucoseAlarm?
    private(set) var suggestion: Suggestion?

    private(set) var lightMode = LightMode.auto
    private(set) var liveActivitiesSystemEnabled: Bool = false

    @ObservationIgnored let uiBindings = UIBindings()

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

        observeUI(appCoordinator.settings) { me, value in me.settings = value }
        observeUI(appCoordinator.preferences) { me, value in me.preferences = value }
        observeUI(appCoordinator.pumpSettings) { me, value in me.pumpSettings = value }

        observeUI(appCoordinator.pumpInfo) { me, value in me.pumpInfo = value }
        observeUI(appCoordinator.pumpStatus) { me, value in me.pumpStatus = value }
        observeUI(appCoordinator.cgmInfo) { me, value in me.cgmInfo = value }
        observeUI(appCoordinator.cgmStatus) { me, value in me.cgmStatus = value }
        observeUI(appCoordinator.isLooping) { me, value in me.isLooping = value }
        observeUI(appCoordinator.manualTempBasal) { me, value in me.manualTempBasal = value }
        observeUI(appCoordinator.pumpStatus, map: { $0?.reservoir }) { me, value in me.pumpReservoir = value }
        observeUI(appCoordinator.lastLoopDate) { me, value in me.lastLoopDate = value }
        observeUI(appCoordinator.bolusProgress) { me, value in me.bolusProgress = value }
        observeUI(appCoordinator.bolusAmount) { me, value in me.bolusAmount = value }
        observeUI(appCoordinator.lastLoopError) { me, value in me.lastLoopError = value }
        observeUI(appCoordinator.alertNotAckUpdates) { me, value in me.alertNotAck = value }
        observeUI(appCoordinator.glucoseAlarm) { me, value in me.glucoseAlarm = value }
        observeUI(appCoordinator.liveActivitiesSystemEnabled) { me, value in me.liveActivitiesSystemEnabled = value }
        observeUI(appCoordinator.settings, map: { $0.lightMode }) { me, value in me.lightMode = value }
        observeUI(appCoordinator.iobTicks, map: { $0?.first?.iob }) { me, value in me.latestIOB = value }
        observeUI(appCoordinator.suggested, map: { $0?.cob }) { me, value in me.latestCOB = value }
        observeUI(appCoordinator.suggested) { me, value in me.suggestion = value }
    }
}
