import Foundation
import LibreTransmitter
import LoopKit
import Swinject

struct Calibration: JSON, Hashable, Identifiable {
    let x: Double
    let y: Double
    var date = Date()

    static let zero = Calibration(x: 0, y: 0)

    var id = UUID()
}

struct CalibrationOptions: Equatable, Sendable {
    var robustFit: Bool = false
    var relaxLimits: Bool = false
}

struct CalibrationFit: Equatable, Sendable {
    var slope: Double = 1
    var intercept: Double = 0
    var fittedSlope: Double = 1
    var fittedIntercept: Double = 0
    /// false when there are too few points, or too little spread between them
    var estimatedSlope: Bool = false
    var robust: Bool = false
    /// how far apart the calibration points sit, in mg/dL of raw sensor value
    var spread: Double = 0
    var count: Int = 0

    var slopeIsLimited: Bool {
        abs(slope - fittedSlope) > 1E-9
    }

    var interceptIsLimited: Bool {
        abs(intercept - fittedIntercept) > 1E-9
    }

    var isLimited: Bool {
        slopeIsLimited || interceptIsLimited
    }

    func calibrate(_ value: Double) -> Double {
        (intercept + slope * value).clamped(CalibrationFitting.valueLimits)
    }
}

enum CalibrationFitting {
    static let valueLimits: ClosedRange<Double> = 0 ... 500

    /// Below this much spread between the calibration points the slope is not estimated at all and
    /// the correction is a pure offset.
    static let minimumSpread: Double = 50

    static let minimumRobustCount = 3

    static func slopeLimits(relaxed: Bool) -> ClosedRange<Double> {
        relaxed ? 0.5 ... 2.0 : 0.8 ... 1.25
    }

    static func interceptLimits(relaxed: Bool) -> ClosedRange<Double> {
        relaxed ? -200 ... 200 : -100 ... 100
    }

    static func fit(_ calibrations: [Calibration], options: CalibrationOptions) -> CalibrationFit {
        guard calibrations.isNotEmpty else { return CalibrationFit() }

        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)
        let spread = (xs.max() ?? 0) - (xs.min() ?? 0)

        let robust = options.robustFit && calibrations.count >= minimumRobustCount
        let estimatedSlope = calibrations.count >= 2 && spread >= minimumSpread

        let fittedSlope: Double
        switch (estimatedSlope, robust) {
        case (false, _): fittedSlope = 1
        case (true, true): fittedSlope = theilSenSlope(xs, ys) ?? 1
        case (true, false): fittedSlope = leastSquaresSlope(xs, ys) ?? 1
        }

        let slope = fittedSlope.clamped(slopeLimits(relaxed: options.relaxLimits))

        let fittedIntercept = robust
            ? median(zip(ys, xs).map { $0 - slope * $1 })
            : average(ys) - slope * average(xs)

        return CalibrationFit(
            slope: slope,
            intercept: fittedIntercept.clamped(interceptLimits(relaxed: options.relaxLimits)),
            fittedSlope: fittedSlope,
            fittedIntercept: fittedIntercept,
            estimatedSlope: estimatedSlope,
            robust: robust,
            spread: spread,
            count: calibrations.count
        )
    }

    private static func leastSquaresSlope(_ xs: [Double], _ ys: [Double]) -> Double? {
        let meanX = average(xs)
        let variance = average(multiply(xs, xs)) - meanX * meanX
        guard abs(variance) > 1E-9 else { return nil }
        return (average(multiply(xs, ys)) - meanX * average(ys)) / variance
    }

    private static func theilSenSlope(_ xs: [Double], _ ys: [Double]) -> Double? {
        var slopes: [Double] = []
        for i in xs.indices {
            for j in xs.index(after: i) ..< xs.endIndex where abs(xs[j] - xs[i]) > 1E-9 {
                slopes.append((ys[j] - ys[i]) / (xs[j] - xs[i]))
            }
        }
        return slopes.isEmpty ? nil : median(slopes)
    }

    private static func median(_ input: [Double]) -> Double {
        guard input.isNotEmpty else { return 0 }
        let sorted = input.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func average(_ input: [Double]) -> Double {
        input.reduce(0, +) / Double(input.count)
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map(*)
    }
}

protocol CalibrationService: Sendable {
    var slope: Double { get }
    var intercept: Double { get }
    var fit: CalibrationFit { get }
    var calibrations: [Calibration] { get }

    func addCalibration(_ calibration: Calibration)
    func removeCalibration(_ calibration: Calibration)
    func removeAllCalibrations()
    func removeLast()

    func calibrate(value: Double) -> Double
}

final class BaseCalibrationService: CalibrationService, Injectable, LifetimeOwner, Sendable, AppService {
    private let storage: FileStorage!
    private let appCoordinator: AppCoordinator!

    let lifetime = Lifetime()

    private let calibrationsLocked: Locked<[Calibration]> = Locked([])
    var calibrations: [Calibration] { calibrationsLocked.value }

    init(resolver: Resolver) {
        storage = resolver.resolve(FileStorage.self)!
        appCoordinator = resolver.resolve(AppCoordinator.self)!
        injectServices(resolver)
    }

    // this is called at the start of the app
    func start() async {
        let loaded = await storage.retrieve(OpenAPS.FreeAPS.calibrations, as: [Calibration].self) ?? []
        calibrationsLocked.mutate { $0 = loaded }

        observe(appCoordinator.newSensorDetectedEvents) { me, _ in
            me.removeAllCalibrations()
        }
    }

    private func mutate(_ body: (inout [Calibration]) -> Void) {
        let snapshot: [Calibration] = calibrationsLocked.mutate {
            body(&$0)
        }
        // Fire-and-forget save; rapid back-to-back mutations could persist out of order.
        // Should be harmless here - mutations do not happen with sub-millisecond intervals (user-initiated or CGM readings).
        Task { await storage.save(snapshot, as: OpenAPS.FreeAPS.calibrations) }
    }

    private var options: CalibrationOptions {
        let settings = appCoordinator.settings.value
        return CalibrationOptions(
            robustFit: settings.calibrationRobustFit,
            relaxLimits: settings.calibrationRelaxLimits
        )
    }

    var fit: CalibrationFit {
        CalibrationFitting.fit(calibrations, options: options)
    }

    var slope: Double {
        fit.slope
    }

    var intercept: Double {
        fit.intercept
    }

    func calibrate(value: Double) -> Double {
        fit.calibrate(value)
    }

    func addCalibration(_ calibration: Calibration) {
        mutate { $0.append(calibration) }
    }

    func removeCalibration(_ calibration: Calibration) {
        mutate { $0.removeAll { $0 == calibration } }
    }

    func removeAllCalibrations() {
        mutate { $0.removeAll() }
    }

    func removeLast() {
        mutate {
            if !$0.isEmpty {
                $0.removeLast()
            }
        }
    }
}
