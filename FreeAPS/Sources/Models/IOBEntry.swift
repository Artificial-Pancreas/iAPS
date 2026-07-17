import Foundation

struct IOBEntry: Codable, Equatable {
    let iob: Decimal
    let activity: Decimal
    let basaliob: Decimal
    let bolusiob: Decimal
    let netbasalinsulin: Decimal
    let bolusinsulin: Decimal
    let iobWithZeroTemp: WithZeroTemp?
    let lastBolusTime: UInt64?
    let lastTemp: LastTemp?
    var time: Date?

    struct WithZeroTemp: JSON, Equatable {
        let iob: Decimal
        let activity: Decimal
        let basaliob: Decimal
        let bolusiob: Decimal
        let netbasalinsulin: Decimal
        let bolusinsulin: Decimal
        let time: Date
    }

    struct LastTemp: JSON, Equatable {
        let rate: Decimal
        let timestamp: Date
        let started_at: Date
        let date: Decimal?
        let duration: Decimal
    }
}

struct IOBEntryShort: Equatable, Comparable {
    let time: Date
    let iob: Decimal
    let activity: Decimal

    static func < (lhs: IOBEntryShort, rhs: IOBEntryShort) -> Bool {
        rhs.time < lhs.time
    }
}

extension IOBEntry {
    static func parseArrayFromJSON(from iob: RawJSON) -> [IOBEntry]? {
        guard let iobData = iob.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds

        do {
            let iobEntries = try decoder.decode([IOBEntry].self, from: iobData)
            return iobEntries
        } catch {
            print("Error decoding IOBEntry array: \(error)\n\(iob)")
            return nil
        }
    }
}
