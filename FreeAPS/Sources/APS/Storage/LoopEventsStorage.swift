import Foundation
import Swinject

protocol LoopEventsStorage: Sendable {
    func storeEvent(_ event: LoopEvent) async
    func recordCrash(_ event: LoopEvent) async
}

actor BaseLoopEventsStorage: LoopEventsStorage, AppService {
    enum Config {
        static let retention: TimeInterval = .hours(26)
        /// a crash reported this close to the launch is what caused the launch
        static let crashAttributionWindow: TimeInterval = .hours(1)
    }

    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    private let launchDate = Date()
    private var appStartEventId: String?
    private var crashRecordedForThisLaunch = false

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start
    func start() async {
        let stored = await storage.retrieve(OpenAPS.Monitor.loopEvents, as: [LoopEvent].self) ?? []
        appCoordinator.setLoopEvents(Self.filterOldAndSort(stored))

        await recordAppStart()
    }

    func storeEvent(_ event: LoopEvent) async {
        let events = await storage.appendAndModify([event], to: OpenAPS.Monitor.loopEvents, uniqBy: \.id) {
            Self.filterOldAndSort($0)
        }
        debug(.service, "loop event stored: \(event.type.rawValue) \(event.message ?? "")")
        appCoordinator.setLoopEvents(events)
    }

    func recordCrash(_ event: LoopEvent) async {
        // A crash reported around the time we started is what caused this launch
        guard abs(launchDate.timeIntervalSince(event.timestamp)) < Config.crashAttributionWindow else {
            await storeEvent(event)
            return
        }

        crashRecordedForThisLaunch = true
        if let appStartEventId {
            await removeEvent(id: appStartEventId)
            self.appStartEventId = nil
        }
        await storeEvent(
            LoopEvent(id: event.id, timestamp: launchDate, type: event.type, message: event.message)
        )
    }

    private func recordAppStart() async {
        // a crash diagnostic already explained this launch
        guard !crashRecordedForThisLaunch else { return }

        let event = LoopEvent(timestamp: launchDate, type: .appStart)
        appStartEventId = event.id
        await storeEvent(event)
    }

    private func removeEvent(id: String) async {
        let (modified, updatedValues) = await storage
            .maybeModify(file: OpenAPS.Monitor.loopEvents, as: LoopEvent.self) { inStorage in
                guard inStorage.contains(where: { $0.id == id }) else {
                    return nil // do not modify
                }
                return Self.filterOldAndSort(inStorage.filter { $0.id != id })
            }
        if modified {
            appCoordinator.setLoopEvents(updatedValues)
        }
    }

    /// newest -> oldest
    private static func filterOldAndSort(_ events: [LoopEvent]) -> [LoopEvent] {
        let oldest = Date.now.subtractingTimeInterval(Config.retention)
        return events
            .filter { $0.timestamp > oldest }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
