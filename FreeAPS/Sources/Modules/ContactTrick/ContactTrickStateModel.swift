import ConnectIQ
import SwiftUI

enum ContactTrickValue: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case bg
    case delta
    case trend
    case time
    case cob
    case iob
    case isf
    case override
    case ring

    var displayName: String {
        switch self {
        case .bg:
            return NSLocalizedString("BG", comment: "")
        case .delta:
            return NSLocalizedString("Delta", comment: "")
        case .trend:
            return NSLocalizedString("Trend", comment: "")
        case .time:
            return NSLocalizedString("Time", comment: "")
        case .cob:
            return NSLocalizedString("COB", comment: "")
        case .iob:
            return NSLocalizedString("IOB", comment: "")
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
    case ring

    var displayName: String {
        switch self {
        case .single:
            return NSLocalizedString("Single", comment: "")
        case .split:
            return NSLocalizedString("Split", comment: "")
        case .ring:
            return NSLocalizedString("Ring", comment: "")
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
                    value: .bg,
                    contactId: nil,
                    displayName: nil,
                    trend: false,
                    ring: false,
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
