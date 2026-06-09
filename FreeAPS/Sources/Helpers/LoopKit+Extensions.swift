import LoopKit

extension Locked: @retroactive @unchecked Sendable where T: Sendable {}

extension DoseEntry: @retroactive @unchecked Sendable {}
