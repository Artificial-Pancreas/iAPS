import HealthKit
import LoopKitUI
import SwiftUI

struct GlucoseRangeView: UIViewControllerRepresentable {
    func makeUIViewController(context _: UIViewControllerRepresentableContext<GlucoseRangeView>) -> UIViewController {
        let unit = HKUnit.millimolesPerLiter
        return GlucoseRangeScheduleTableViewController(allowedValues: unit.allowedCorrectionRangeValues(), unit: unit)
    }

    func updateUIViewController(
        _: UIViewController,
        context _: UIViewControllerRepresentableContext<GlucoseRangeView>
    ) {}
}

extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = {
        HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    }()

    static let millimolesPerLiter: HKUnit = {
        HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
    }()

    func allowedCorrectionRangeValues() -> [Double] {
        switch self {
        case HKUnit.milligramsPerDeciliter:
            return (60 ... 180).map { Double($0) }
        case HKUnit.millimolesPerLiter:
            return (33 ... 100).map { Double($0) / 10.0 }
        default:
            return []
        }
    }
}
