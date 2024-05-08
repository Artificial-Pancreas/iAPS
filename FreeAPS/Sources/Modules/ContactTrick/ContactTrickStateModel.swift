import ConnectIQ
import SwiftUI

enum ContactTrickValue: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case none
    case glucose
    case eventualBG
    case delta
    case trend
    case lastLoopDate
    case cob
    case iob
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
        case .lastLoopDate:
            return NSLocalizedString("Last loop date", comment: "")
        case .cob:
            return NSLocalizedString("COB", comment: "")
        case .iob:
            return NSLocalizedString("IOB", comment: "")
        case .ring:
            return NSLocalizedString("Loop status", comment: "")
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
    case cob
    case iobcob

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("Don't show", comment: "")
        case .loop:
            return NSLocalizedString("Loop status", comment: "")
        case .iob:
            return NSLocalizedString("IOB", comment: "")
        case .cob:
            return NSLocalizedString("COB", comment: "")
        case .iobcob:
            return NSLocalizedString("IOB+COB", comment: "")
        }
    }
}

extension ContactTrick {
    final class StateModel: BaseStateModel<Provider> {
        @Published private(set) var syncInProgress = false
        @Published private(set) var items: [Item] = []
        @Published private(set) var changed: Bool = false

        override func subscribe() {
            items = provider.contacts.enumerated().map { index, contact in
                Item(
                    index: index,
                    entry: contact
                )
            }
            changed = false
        }

        func add() {
            let newItem = Item(
                index: items.count,
                entry: ContactTrickEntry()
            )

            items.append(newItem)
            changed = true
        }

        func update(_ atIndex: Int, _ value: ContactTrickEntry) {
            items[atIndex].entry = value
            changed = true
        }

        func remove(atOffsets: IndexSet) {
            items.remove(atOffsets: atOffsets)
            changed = true
        }

        func save() {
            syncInProgress = true
            let contacts = items.map { item -> ContactTrickEntry in
                item.entry
            }
            provider.saveContacts(contacts)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    self.syncInProgress = false
                    self.changed = false
                } receiveValue: { contacts in
                    contacts.enumerated().forEach { index, item in
                        self.items[index].entry = item
                    }
                }
                .store(in: &lifetime)
        }
    }
}
