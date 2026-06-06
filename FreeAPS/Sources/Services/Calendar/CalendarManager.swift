import CoreData
import EventKit
import Swinject

protocol CalendarManager: Sendable {
    func requestAccessIfNeeded() async -> Bool
    func calendarIDs() async -> [String]
    var currentCalendarID: String? { get async }
    func setCurrentCalendarID(_ id: String?) async
    func createEvent(for glucose: BloodGlucose?, delta: Int?) async
}

actor BaseCalendarManager: CalendarManager, Injectable {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var appCoordinator: AppCoordinator!

    @Persisted(key: "CalendarManager.currentCalendarID") var persistedCurrentCalendarID: String? = nil

    private let eventStore = EKEventStore()

    private var settings: FreeAPSSettings!

    private var lifetime = Lifetime()

    init(resolver: Resolver) {
        injectServices(resolver)

        Task {
            await self.subscribe()
        }
    }

    private func subscribe() async {
        self.settings = await settingsManager.settings

        observe(appCoordinator.settingsUpdates, in: &lifetime) { settings in
            await self.settingsUpdated(settings)
        }

        observe(appCoordinator.glucoseHistoryUpdates, in: &lifetime) { _ in
            await self.setupGlucose()
        }

        observe(appCoordinator.suggestions, in: &lifetime) { _ in
            await self.setupGlucose()
        }

        observe(appCoordinator.pumpHistoryUpdates, in: &lifetime) { _ in
            await self.setupGlucose()
        }

        await setupGlucose()
    }

    private func settingsUpdated(_ settings: FreeAPSSettings) {
        self.settings = settings
    }

    func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            return await requestFullAccess()
        case .denied,
             .restricted:
            return false
        case .authorized,
             .fullAccess:
            return true
        case .writeOnly:
            return await requestFullAccess()
        @unknown default:
            warning(.service, "Unknown calendar access status")
            return false
        }
    }

    private func requestFullAccess() async -> Bool {
        if #available(iOS 17, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                warning(.service, "Calendar access request failed", error: error)
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error { warning(.service, "Calendar access request failed", error: error) }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    var currentCalendarID: String? {
        persistedCurrentCalendarID
    }

    func setCurrentCalendarID(_ id: String?) async {
        persistedCurrentCalendarID = id
    }

    func calendarIDs() -> [String] {
        eventStore.calendars(for: .event).map(\.title)
    }

    func createEvent(for glucose: BloodGlucose?, delta: Int?) {
        guard settings.useCalendar else { return }

        guard let calendar = currentCalendar else { return }

        deleteAllEvents(in: calendar)

        guard let glucose = glucose, let glucoseValue = glucose.glucose else { return }

        // create an event now
        let event = EKEvent(eventStore: eventStore)

        // Calendar settings
        let displeyCOBandIOB = settings.displayCalendarIOBandCOB
        let displayEmojis = settings.displayCalendarEmojis

        // Latest Loop data (from CoreData)
        var freshLoop: Double = 20
        var lastLoop: Reasons?
        if displeyCOBandIOB || displayEmojis, let recentLoop = CoreDataStorage().fetchReason() {
            lastLoop = recentLoop
            freshLoop = -1 * (recentLoop.date ?? .distantPast).timeIntervalSinceNow.minutes
        }

        var glucoseIcon = "🟢"
        if displayEmojis {
            glucoseIcon = Double(glucoseValue) <= Double(settings.low) ? "🔴" : glucoseIcon
            glucoseIcon = Double(glucoseValue) >= Double(settings.high) ? "🟠" : glucoseIcon
            glucoseIcon = freshLoop > 15 ? "🚫" : glucoseIcon
        }

        let glucoseText = glucoseFormatter
            .string(from: (
                settings.units == .mmolL ?glucoseValue.asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!
        let directionText = glucose.direction?.symbol ?? "↔︎"
        let deltaText = delta
            .map {
                Self.deltaFormatter
                    .string(from: (settings.units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
            } ?? "--"

        let iobText = lastLoop != nil ? (Self.iobFormatter.string(from: (lastLoop?.iob ?? 0) as NSNumber) ?? "") : ""
        let cobText = lastLoop != nil ? (Self.cobFormatter.string(from: (lastLoop?.cob ?? 0) as NSNumber) ?? "") : ""

        var glucoseDisplayText = displayEmojis ? glucoseIcon + " " : ""
        glucoseDisplayText += glucoseText + " " + directionText + " " + deltaText

        var iobDisplayText = ""
        var cobDisplayText = ""

        if displeyCOBandIOB {
            if displayEmojis {
                iobDisplayText += "💉"
                cobDisplayText += "🥨"
            } else {
                iobDisplayText += "IOB:"
                cobDisplayText += "COB:"
            }
            iobDisplayText += " " + iobText
            cobDisplayText += " " + cobText
            event.location = iobDisplayText + " " + cobDisplayText
        }

        event.title = glucoseDisplayText
        event.notes = "iAPS"
        event.startDate = Date()
        event.endDate = Date(timeIntervalSinceNow: 60 * 10)
        event.calendar = calendar

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            warning(.service, "Cannot create calendar event", error: error)
        }
    }

    private var currentCalendar: EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        guard calendars.isNotEmpty else { return nil }
        return calendars.first { $0.title == self.persistedCurrentCalendarID }
    }

    private func deleteAllEvents(in calendar: EKCalendar) {
        let predicate = eventStore.predicateForEvents(
            withStart: Date(timeIntervalSinceNow: -24 * 3600),
            end: Date(),
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)

        for event in events {
            do {
                try eventStore.remove(event, span: .thisEvent)
            } catch {
                warning(.service, "Cannot remove calendar events", error: error)
            }
        }
    }

    private var glucoseFormatter: NumberFormatter {
        switch settings.units {
        case .mmolL: return Self.glucoseFormatterMmol
        case .mgdL: return Self.glucoseFormatterMgdl
        }
    }

    private static let glucoseFormatterMmol = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let glucoseFormatterMgdl = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let deltaFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }()

    private static let iobFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let cobFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    func setupGlucose() async {
        let glucose = await glucoseStorage.retrieveRaw()
        let recentGlucose = glucose.last
        let glucoseDelta: Int?
        if glucose.count >= 2 {
            glucoseDelta = (recentGlucose?.glucose ?? 0) - (glucose[glucose.count - 2].glucose ?? 0)
        } else {
            glucoseDelta = nil
        }
        createEvent(for: recentGlucose, delta: glucoseDelta)
    }
}

extension BloodGlucose.Direction {
    var symbol: String {
        switch self {
        case .tripleUp:
            return "↑↑↑"
        case .doubleUp:
            return "↑↑"
        case .singleUp:
            return "↑"
        case .fortyFiveUp:
            return "↗︎"
        case .flat:
            return "→"
        case .fortyFiveDown:
            return "↘︎"
        case .singleDown:
            return "↓"
        case .doubleDown:
            return "↓↓"
        case .tripleDown:
            return "↓↓↓"
        case .none:
            return "↔︎"
        case .notComputable:
            return "↔︎"
        case .rateOutOfRange:
            return "↔︎"
        }
    }
}
