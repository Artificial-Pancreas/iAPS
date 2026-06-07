import Combine
import Foundation
import Observation

@MainActor
@Observable final class AppUIState {
    private(set) var pumpInfo: PumpDisplayInfo?
    private(set) var pumpStatus: PumpDisplayStatus?
    private(set) var cgmInfo: CgmDisplayInfo?
    private(set) var cgmStatus: CgmDisplayStatus?
    private(set) var isLooping = false
    private(set) var manualTempBasal = false
    private(set) var pumpReservoir: Decimal?
    private(set) var lastLoopDate: Date?
    private(set) var bolusProgress: Decimal?
    private(set) var bolusAmount: Decimal?
    private(set) var bolusInProgress: Bool = false
    private(set) var alertNotAckUpdates: Bool = false
    private(set) var lastLoopError: Error?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(appCoordinator: AppCoordinator) {
        bind(appCoordinator.pumpInfo, to: \.pumpInfo)
        bind(appCoordinator.pumpStatus, to: \.pumpStatus)
        bind(appCoordinator.cgmInfo, to: \.cgmInfo)
        bind(appCoordinator.cgmStatus, to: \.cgmStatus)
        bind(appCoordinator.isLooping, to: \.isLooping)
        bind(appCoordinator.manualTempBasal, to: \.manualTempBasal)
        bind(appCoordinator.pumpReservoir, to: \.pumpReservoir)
        bind(appCoordinator.lastLoopDate, to: \.lastLoopDate)
        bind(appCoordinator.bolusProgress, to: \.bolusProgress)
        bind(appCoordinator.bolusAmount, to: \.bolusAmount)
        bind(appCoordinator.bolusInProgress, to: \.bolusInProgress)
        bind(appCoordinator.alertNotAckUpdates, to: \.alertNotAckUpdates)
        bind(appCoordinator.lastLoopError, to: \.lastLoopError)
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
