import HealthKit

/// Shim mapping LoopAlgorithm's quantity types onto HealthKit's, so that
/// LibreLoop (written against LoopKit `next-dev`) compiles against the
/// `dev`-era LoopKit that iAPS uses, where these APIs still take HKQuantity.
///
/// Built as a dynamic framework so Swift autolinking resolves it in client
/// modules exactly as it does for LoopKit and LoopKitUI. It is embedded into the
/// app by the FreeAPS target; the plugin finds it at runtime via @rpath.
public typealias LoopQuantity = HKQuantity
public typealias LoopUnit = HKUnit

public extension LoopUnit {
    var localizedShortUnitString: String {
        switch self {
        case .millimolesPerLiter: return NSLocalizedString(
                "mmol/L",
                comment: "The short unit display string for millimoles of glucose per liter"
            )
        case .milligramsPerDeciliter: return NSLocalizedString(
                "mg/dL",
                comment: "The short unit display string for milligrams of glucose per decilter"
            )
        //        case .internationalUnit: return NSLocalizedString("U", comment: "The short unit display string for international units of insulin")
        //        case .gram: return NSLocalizedString("g", comment: "The short unit display string for grams")
        default: return String(describing: self)
        }
    }
}

/// LoopKit declares these same units internally (LoopKit/Extensions/HKUnit.swift),
/// so they are not visible to plugins. Upstream, LibreLoop gets them as public
/// `LoopUnit` cases from LoopAlgorithm; re-expose them publicly here.
public extension HKUnit {
    static let milligramsPerDeciliter =
        HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))

    static let millimolesPerLiter =
        HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())

    static let milligramsPerDeciliterPerMinute =
        HKUnit.milligramsPerDeciliter.unitDivided(by: .minute())

    static let millimolesPerLiterPerMinute =
        HKUnit.millimolesPerLiter.unitDivided(by: .minute())
}
