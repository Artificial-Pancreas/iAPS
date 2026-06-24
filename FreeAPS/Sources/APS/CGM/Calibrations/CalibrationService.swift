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

protocol CalibrationService: Sendable {
    var slope: Double { get }
    var intercept: Double { get }
    var calibrations: [Calibration] { get }

    func addCalibration(_ calibration: Calibration)
    func removeCalibration(_ calibration: Calibration)
    func removeAllCalibrations()
    func removeLast()

    func calibrate(value: Double) -> Double
}

final class BaseCalibrationService: CalibrationService, Injectable, LifetimeOwner, Sendable, AppService {
    private enum Config {
        static let minSlope = 0.8
        static let maxSlope = 1.25
        static let minIntercept = -100.0
        static let maxIntercept = 100.0
        static let maxValue = 500.0
        static let minValue = 0.0
    }

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

    var slope: Double { Self.slope(calibrations) }
    var intercept: Double { Self.intercept(calibrations) }
    func calibrate(value: Double) -> Double { Self.calibrate(value, calibrations) }

    private static func slope(_ calibrations: [Calibration]) -> Double {
        guard calibrations.count >= 2 else {
            return 1
        }

        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)
        let sum1 = average(multiply(xs, ys)) - average(xs) * average(ys)
        let sum2 = average(multiply(xs, xs)) - pow(average(xs), 2)
        let slope = sum1 / sum2

        return min(max(slope, Config.minSlope), Config.maxSlope)
    }

    private static func intercept(_ calibrations: [Calibration]) -> Double {
        guard calibrations.count >= 1 else {
            return 0
        }
        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)

        let intercept = average(ys) - slope(calibrations) * average(xs)

        return min(max(intercept, Config.minIntercept), Config.maxIntercept)
    }

    private static func calibrate(_ value: Double, _ calibrations: [Calibration]) -> Double {
        linearRegression(calibrations, value)
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
        mutate { if !$0.isEmpty { $0.removeLast() } }
    }

    private static func average(_ input: [Double]) -> Double {
        input.reduce(0, +) / Double(input.count)
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map(*)
    }

    private static func linearRegression(_ calibrations: [Calibration], _ x: Double) -> Double {
        (intercept(calibrations) + slope(calibrations) * x).clamped(Config.minValue ... Config.maxValue)
    }
}
