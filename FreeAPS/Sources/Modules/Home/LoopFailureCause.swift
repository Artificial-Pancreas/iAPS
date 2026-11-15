import Foundation

/// Why a loop failed, grouped at read time from the free text the app stores with a failed loop (`LoopStatRecord.error`,
/// also its `loopStatus`: `APSManager.loop` stores the error description in both). No attribute of its own: the text is
/// what there is, for the records stored before too.
///
/// The text is cleaned first (`clean`: numbers, ids, dates and times stripped, the spaces collapsed), so the same failure
/// at another time or of another amount is the same cause. The known families (`APSError`'s descriptions, the pump
/// managers' errors behind "Pump error:") map to the loop event types the main chart shows, as `LoopEventType(failure:)`
/// and the pump command failures (`DeviceDataManager.recordCommandFailure`) name them (its title, symbol and colour);
/// any other text is a cause of its own, `.loopFailed` with the cleaned text as its label. Compared and hashed by the
/// type and the cleaned text without case: "Pump error: Timeout" and "Pump error: timeout" are one cause, shown as the
/// first one met.
///
/// The families key on `APSError`'s English prefixes ("Pump error:", "APS error:", "Error: Invalid glucose:", ...: not
/// localized; "Pump is Busy." is, and is matched in both). What follows "Pump error:" is the pump manager's description,
/// often localized: its words are matched in English only, so a localized driver error falls into the pump's group
/// (communication, as the chart names a pump error it can't tell apart), not its own.
struct LoopFailureCause: Hashable, Sendable {
    enum Config {
        /// the cleaned text is cut to this many characters (a pump manager's description can be long)
        static let maxLength = 120
        /// the texts a `Memo` keeps; all forgotten beyond
        static let memoSize = 1000
    }

    let type: LoopEventType
    /// the cleaned text, as stored; the label of a `.loopFailed` cause
    let message: String
    /// `message` without case: the identity
    private let key: String

    init(type: LoopEventType, message: String) {
        self.type = type
        self.message = message
        key = message.lowercased()
    }

    static func == (lhs: LoopFailureCause, rhs: LoopFailureCause) -> Bool {
        lhs.type == rhs.type && lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(key)
    }

    /// what the cause is called: the event type's title, or for a text of no known family the text itself
    var title: String {
        type == .loopFailed ? message : type.title
    }

    /// a cause of no known family: its own group (`title` is its text)
    var isUngrouped: Bool { type == .loopFailed }
}

extension LoopFailureCause {
    /// The cause of a failed loop: its stored error, or its status when there is none (the status holds the error too);
    /// "Loop failed" without either.
    static func of(error: String?, status: String?) -> LoopFailureCause {
        let text = [error, status].compactMap { $0 }.first { !clean($0).isEmpty } ?? ""
        let message = clean(text)
        guard !message.isEmpty else {
            return LoopFailureCause(type: .loopFailed, message: LoopEventType.loopFailed.title)
        }
        return LoopFailureCause(type: family(of: message), message: message)
    }

    /// The family of a cleaned text, by the descriptions `APSError` gives (`errorDescription`), and for a pump error by
    /// the pump manager's words (LoopKit's `PumpManagerError` descriptions, the drivers' own texts).
    static func family(of message: String) -> LoopEventType {
        let text = message.lowercased()
        let starts = { (prefix: String) in text.hasPrefix(prefix) }
        if text.contains("bolus view") {
            return .bolusView
        }
        if starts("manual basal temp") {
            return .manualTempBasal
        }
        if busyPrefixes.contains(where: starts) || text.contains("bolus is in progress") {
            return .pumpBusy
        }
        if starts("error: invalid glucose") {
            return .glucoseData
        }
        if starts("error: invalid pump state") {
            return text.contains("suspend") ? .pumpSuspended : .pumpNotConfigured
        }
        if starts("pump not configured") || starts("pump not set") {
            return .pumpNotConfigured
        }
        if starts("aps error") {
            // also the failed resume before the loop: an `APSError.apsError`, as the chart names it
            return .algorithm
        }
        if starts("sync error") {
            return .pumpCommunication
        }
        if starts("pump error") {
            // not a `PumpManagerError` (or not known by its words): the pump's communication, as the chart names it
            return pumpFamily(of: text) ?? .pumpCommunication
        }
        // a pump manager's error without the prefix
        return pumpFamily(of: text) ?? .loopFailed
    }

    /// "Pump is Busy." as stored: in English, or in the language the app ran in (`APSError.bolusInProgress` localizes
    /// it)
    private static let busyPrefixes: [String] = {
        let english = "pump is busy"
        let localized = NSLocalizedString("Pump is Busy.", comment: "Pump Error")
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return localized.isEmpty || localized == english ? [english] : [english, localized]
    }()

    /// The pump manager's words (`PumpManagerError`'s cases, `LoopEventType(pumpManagerError:)`): uncertain delivery,
    /// the pump in a state that refuses the command, a failed connection or command, a configuration; nil for others.
    private static func pumpFamily(of text: String) -> LoopEventType? {
        if text.contains("uncertain") {
            return .deliveryUncertain
        }
        // `.deviceState`: LoopKit's own description, and the drivers' (a pod fault, suspended, a bolus running, busy,
        // not set up)
        let deviceState = [
            "device refused", "fault", "suspend", "bolus in progress", "bolussing", "bolusing", "busy", "occlu",
            "setup is not complete", "no pod paired"
        ]
        if deviceState.contains(where: text.contains) {
            return .pumpDeviceState
        }
        let communication = [
            "communication", "comms", "connection", "connect", "no response", "not responding", "timeout", "timed out",
            "time out", "bluetooth", "unreachable", "not reachable", "disconnected", "rileylink", "radio"
        ]
        if communication.contains(where: text.contains) {
            return .pumpCommunication
        }
        if text.contains("configur") {
            return .pumpConfiguration
        }
        return nil
    }

    // MARK: - Cleaning

    /// the patterns, compiled once, and their templates, in order
    private static let patterns: [(regex: NSRegularExpression, template: String)] = sources.map { source in
        (try! NSRegularExpression(pattern: source.pattern), source.template)
    }

    private static let sources: [(pattern: String, template: String)] = [
        // UUIDs
        (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#, ""),
        // ISO and Foundation dates with their times and zones: "2026-11-03 10:15:30 +0000", "2026-11-03T10:15:30.123Z"
        (#"\d{4}-\d{2}-\d{2}([ T]\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?)?( ?(Z|[+-]\d{2}:?\d{2}))?"#, ""),
        // clock times: "10:15", "10:15:30", "10:15 AM"
        (#"\b\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?( ?[AaPp]\.?[Mm]\.?)?"#, ""),
        // hex: "0x1F2E"
        (#"\b0x[0-9a-fA-F]+\b"#, ""),
        // other ids: long runs of hex digits with a digit in them
        (#"\b(?=[0-9a-fA-F]*\d)[0-9a-fA-F]{12,}\b"#, ""),
        // numbers: "2.5", "-1", "1,234", "#12"; not inside a word ("G7", "G12")
        (#"(?<![\p{L}\d])#?[-+]?\d+([.,]\d+)*"#, ""),
        // what the stripping left empty: "()", "[ ]", "( .)", "=,"
        (#"\(\s*[.,;:=]?\s*\)|\[\s*[.,;:=]?\s*\]|\{\s*[.,;:=]?\s*\}"#, ""),
        (#"\s*=\s*(?=[,;)\]}]|$)"#, ""),
        // runs of separators the stripping left: ", ,", ": :"
        (#"\s*([,;:])(\s*[,;:])+"#, "$1"),
        // spaces before punctuation, and runs of spaces
        (#"\s+([,;:.!?)\]])"#, "$1"),
        (#"\s{2,}"#, " ")
    ]

    /// The text without numbers, ids, dates and times, its spaces collapsed, trimmed (with any separator left at its
    /// end), and cut to `Config.maxLength`.
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\n", with: " ")
        for (regex, template) in patterns {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-")))
        if result.count > Config.maxLength {
            result = String(result.prefix(Config.maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return result
    }
}

extension LoopFailureCause {
    /// The causes of the texts met, kept over the reads (a failure's text repeats, its cleaning is a dozen regex passes):
    /// `Config.memoSize` texts at most, all forgotten beyond. Thread-safe: the reads run on Core Data's queues.
    final class Memo: @unchecked Sendable {
        private struct Key: Hashable {
            let error: String?
            let status: String?
        }

        private let lock = NSLock()
        private var causes: [Key: LoopFailureCause] = [:]

        /// `LoopFailureCause.of`, once per text
        func cause(error: String?, status: String?) -> LoopFailureCause {
            let key = Key(error: error, status: status)
            if let cause = lock.withLock({ causes[key] }) {
                return cause
            }
            let cause = LoopFailureCause.of(error: error, status: status)
            lock.withLock {
                if causes.count >= Config.memoSize {
                    causes.removeAll(keepingCapacity: true)
                }
                causes[key] = cause
            }
            return cause
        }

        /// the texts kept, for the tests
        var count: Int { lock.withLock { causes.count } }
    }
}
