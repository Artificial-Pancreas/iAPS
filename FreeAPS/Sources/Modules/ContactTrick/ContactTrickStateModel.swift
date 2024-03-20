import ConnectIQ
import SwiftUI

enum ContactTrickValue: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case none
    case glucose
    case eventualBG
    case delta
    case trend
    case glucoseDate
    case lastLoopDate
    case cob
    case iob
    case bolusRecommended
    case carbsRequired
    case isf
    case override
    case ring

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("None", comment: "")
        case .glucose:
            return NSLocalizedString("Glucose", comment: "")
        case .eventualBG:
            return NSLocalizedString("Eventual BG", comment: "")
        case .delta:
            return NSLocalizedString("Delta", comment: "")
        case .trend:
            return NSLocalizedString("Trend", comment: "")
        case .glucoseDate:
            return NSLocalizedString("Glucose date", comment: "")
        case .lastLoopDate:
            return NSLocalizedString("Last loop date", comment: "")
        case .cob:
            return NSLocalizedString("COB", comment: "")
        case .iob:
            return NSLocalizedString("IOB", comment: "")
        case .bolusRecommended:
            return NSLocalizedString("Bolus recommended", comment: "")
        case .carbsRequired:
            return NSLocalizedString("Carbs required", comment: "")
        case .isf:
            return NSLocalizedString("ISF", comment: "")
        case .override:
            return NSLocalizedString("Override %", comment: "")
        case .ring:
            return NSLocalizedString("Ring", comment: "")
        }
    }
}

enum ContactTrickLayout: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case single
    case split

    var displayName: String {
        switch self {
        case .single:
            return NSLocalizedString("Single", comment: "")
        case .split:
            return NSLocalizedString("Split", comment: "")
        }
    }
}

enum ContactTrickLargeRing: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case none
    case loop
    case iob

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("Don't show", comment: "")
        case .loop:
            return NSLocalizedString("Loop status", comment: "")
        case .iob:
            return NSLocalizedString("IOB", comment: "")
        }
    }
}

extension ContactTrick {
    final class StateModel: BaseStateModel<Provider> {
        @Published var syncInProgress = false
        @Published var items: [Item] = []

        override func subscribe() {
            items = provider.contacts.enumerated().map { index, contact in
                Item(
                    index: index,
                    entry: contact
                )
            }
        }

        func add() {
            let newItem = Item(
                index: items.count,
                entry: ContactTrickEntry(
                    enabled: false,
                    layout: .single,
                    contactId: nil,
                    displayName: nil,
                    darkMode: true,
                    fontSize: 100,
                    fontName: "Default Font",
                    fontWeight: .medium
                )
            )

            items.append(newItem)
        }

        func save() {
            syncInProgress = true
            let contacts = items.map { item -> ContactTrickEntry in
                item.entry
            }
            provider.saveContacts(contacts)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    print("saved!")
                    self.syncInProgress = false
                } receiveValue: {}
                .store(in: &lifetime)
        }
    }
}
