import LoopKit

extension Locked: @retroactive @unchecked Sendable where T: Sendable {}

extension PumpManagerStatus: @retroactive @unchecked Sendable {}
extension DoseEntry: @retroactive @unchecked Sendable {}
extension RepeatingScheduleValue: @retroactive @unchecked Sendable {}
extension BasalRateSchedule: @retroactive @unchecked Sendable {}
