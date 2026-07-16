import LoopKit

extension Locked: @retroactive @unchecked Sendable where T: Sendable {}

extension DoseEntry {
    func unitsPerHourAdjustedForConcentration(_ concentration: Double) -> Decimal {
        Self.fromDeviceUnits(unitsPerHour, concentration: concentration)
    }

    func unitsInDeliverableIncrementsAdjustedForConcentration(_ concentration: Double) -> Decimal {
        Self.fromDeviceUnits(unitsInDeliverableIncrements, concentration: concentration)
    }

    func deliveredUnitsAdjustedForConcentration(_ concentration: Double) -> Decimal? {
        guard let deliveredUnits = self.deliveredUnits else { return nil }
        return Self.fromDeviceUnits(deliveredUnits, concentration: concentration)
    }

    static func toDeviceUnits(_ units: Decimal, concentration: Double) -> Double {
        let concentration = Decimal(concentration)
        return concentration != 1 ? Double((units / concentration).rounded(to: 3)) : Double(units.rounded(to: 3))
    }

    static func fromDeviceUnits(_ units: Double, concentration: Double) -> Decimal {
        let concentration = Decimal(concentration)
        let units = Decimal(units)
        return concentration != 1 ? (units * concentration).rounded(to: 3) : units.rounded(to: 3)
    }
}
