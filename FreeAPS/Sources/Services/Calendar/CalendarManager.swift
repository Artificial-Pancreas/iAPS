import Combine
import CoreData
import EventKit
import Swinject

protocol CalendarManager {
    func requestAccessIfNeeded() -> AnyPublisher<Bool, Never>
    func calendarIDs() -> [String]
    var currentCalendarID: String? { get set }
    func createEvent(for glucose: BloodGlucose?, delta: Int?)
}

final class BaseCalendarManager: CalendarManager, Injectable {
    private lazy var eventStore: EKEventStore = { EKEventStore() }()

    @Persisted(key: "CalendarManager.currentCalendarID") var currentCalendarID: String? = nil
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
        broadcaster.register(GlucoseObserver.self, observer: self)
        setupGlucose()
    }

    let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()

    func requestAccessIfNeeded() -> AnyPublisher<Bool, Never> {
        Future { promise in
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .notDetermined:
                #if swift(>=5.9)
                    if #available(iOS 17.0, *) {
                        EKEventStore().requestFullAccessToEvents(completion: { (granted: Bool, error: Error?) -> Void in
                            if let error = error {
                                warning(.service, "Calendar access not granted", error: error)
                            }
                            promise(.success(granted))
                        })
                    } else {
                        EKEventStore().requestAccess(to: .event) { granted, error in
                            if let error = error {
                                warning(.service, "Calendar access not granted", error: error)
                            }
                            promise(.success(granted))
                        }
                    }
                #else
                    EKEventStore().requestAccess(to: .event) { granted, error in
                        if let error = error {
                            warning(.service, "Calendar access not granted", error: error)
                        }
                        promise(.success(granted))
                    }
                #endif
            case .denied,
                 .restricted:
                promise(.success(false))
            case .authorized:
                promise(.success(true))

            #if swift(>=5.9)
                case .fullAccess:
                    promise(.success(true))
                case .writeOnly:
                    if #available(iOS 17.0, *) {
                        EKEventStore().requestFullAccessToEvents(completion: { (granted: Bool, error: Error?) -> Void in
                            if let error = error {
                                print("Calendar access not upgraded")
                                warning(.service, "Calendar access not upgraded", error: error)
                            }
                            promise(.success(granted))
                        })
                    }
            #endif

            @unknown default:
                warning(.service, "Unknown calendar access status")
                promise(.success(false))
            }
        }.eraseToAnyPublisher()
    }

    func calendarIDs() -> [String] {
        EKEventStore().calendars(for: .event).map(\.title)
    }

    func createEvent(for glucose: BloodGlucose?, delta: Int?) {
        guard settingsManager.settings.useCalendar else { return }

        guard let calendar = currentCalendar else { return }

        deleteAllEvents(in: calendar)

        guard let glucose = glucose, let glucoseValue = glucose.glucose else { return }

        // create an event now
        let event = EKEvent(eventStore: eventStore)

        // Calendar settings
        let displeyCOBandIOB = settingsManager.settings.displayCalendarIOBandCOB
        let displayEmojis = settingsManager.settings.displayCalendarEmojis

        // Latest Loop data (from CoreData)
        var freshLoop: Double = 20
        var lastLoop = [LastLoop]()
        if displeyCOBandIOB || displayEmojis {
            coredataContext.performAndWait {
                let requestLastLoop = LastLoop.fetchRequest() as NSFetchRequest<LastLoop>
                let sortLoops = NSSortDescriptor(key: "timestamp", ascending: false)
                requestLastLoop.sortDescriptors = [sortLoops]
                requestLastLoop.fetchLimit = 1
                try? lastLoop = coredataContext.fetch(requestLastLoop)
            }
            freshLoop = -1 * (lastLoop.first?.timestamp ?? .distantPast).timeIntervalSinceNow.minutes
        }

        var glucoseIcon = "🟢"
        if displayEmojis {
            glucoseIcon = Double(glucoseValue) <= Double(settingsManager.settings.low) ? "🔴" : glucoseIcon
            glucoseIcon = Double(glucoseValue) >= Double(settingsManager.settings.high) ? "🟠" : glucoseIcon
            glucoseIcon = freshLoop > 15 ? "🚫" : glucoseIcon
        }

        let glucoseText = glucoseFormatter
            .string(from: Double(
                settingsManager.settings.units == .mmolL ?glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!
        let directionText = glucose.direction?.symbol ?? "↔︎"
        let deltaText = delta
            .map {
                deltaFormatter
                    .string(from: Double(settingsManager.settings.units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
            } ?? "--"

        let iobText = iobFormatter.string(from: (lastLoop.first?.iob ?? 0) as NSNumber) ?? ""
        let cobText = cobFormatter.string(from: (lastLoop.first?.cob ?? 0) as NSNumber) ?? ""

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

    var currentCalendar: EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        guard calendars.isNotEmpty else { return nil }
        return calendars.first { $0.title == self.currentCalendarID }
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }

    private var iobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var cobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    func setupGlucose() {
        let glucose = glucoseStorage.recent()
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

extension BaseCalendarManager: GlucoseObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
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
