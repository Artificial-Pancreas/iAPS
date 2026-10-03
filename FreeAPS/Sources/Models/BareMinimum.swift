import Foundation

struct BareMinimum: JSON, Equatable {
    var id: String
    var created_at: Date
    var Build_Version: String
    var Branch: String
    /// App-behaviour memory telemetry only — never hardware-identifying fields.
    /// See MemoryStats for the tier split.
    var Memory: MemoryStats?
}
