import BackgroundTasks
import Foundation
import UIKit

/// A background processing task that gives iAPS a chance to recover when Bluetooth stops waking it.
///
/// With a CGM that connects on its own (Dexcom G7, Libre) and a pod that is connected only on
/// demand, the CGM's five-minute connection is the only event that wakes the app in the
/// background. On some phones (an iPhone 17 Pro on iOS 27, so far) iOS has been seen to stop
/// delivering those connections to the suspended app for hours while the Dexcom app on the same
/// phone kept receiving readings. The process stays alive but never runs, so nothing inside it
/// can notice, and the "no loop" notifications are the only sign.
///
/// `BGTaskScheduler` is the other way a suspended app gets CPU time: iOS runs a processing task
/// when the phone is idle, typically locked and charging, which is exactly when the outage
/// happens. When the task runs and the last glucose reading is stale, the watchdog asks the CGM
/// manager to fetch again (for the G7 that re-issues the connection and the connection-event
/// registration), lets a loop run, and tells the user. When readings are current it does nothing.
///
/// iOS gives no guarantee about when, or whether, a processing task runs, and Low Power Mode
/// suppresses them entirely. This is a recovery attempt, not a keep-alive.
final class BackgroundWatchdog {
    static let shared = BackgroundWatchdog()

    /// Listed under BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "com.freeapsx.background-task.watchdog"

    /// The earliest the next task may run after a submission. iOS usually runs it later.
    private let interval: TimeInterval = 15 * 60
    /// A latest reading older than this means the Bluetooth wake-ups have stopped.
    private let staleAfter: TimeInterval = 15 * 60
    /// How long a stale run keeps the app awake for the CGM to reconnect before completing.
    private let recoveryWindow: TimeInterval = 15

    private var isRegistered = false
    /// The reading that was current when the user was last notified, so one outage produces
    /// one notification however many times the task runs during it.
    private var notifiedForReadingAt: Date?

    private init() {}

    /// Registers the task handler. Must run before `application(_:didFinishLaunchingWithOptions:)`
    /// returns, or iOS refuses the registration.
    func register() {
        guard !isRegistered else { return }
        isRegistered = true

        let accepted = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            DispatchQueue.main.async { self.run(task) }
        }
        debug(.default, "Background watchdog: handler \(accepted ? "registered" : "NOT registered")")
    }

    /// Asks iOS for a run no earlier than `interval` from now. A new submission replaces the
    /// pending one, so calling this often is harmless.
    func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            warning(.default, "Background watchdog: could not schedule the task", error: error)
        }
    }

    private func run(_ task: BGProcessingTask) {
        dispatchPrecondition(condition: .onQueue(.main))

        // Each submission fires once: keep the chain going whatever happens below.
        schedule()

        var isCompleted = false
        let started = Date()
        let complete: (Bool) -> Void = { success in
            guard !isCompleted else { return }
            isCompleted = true
            debug(.default, "Background watchdog: run completed after \(Int(Date().timeIntervalSince(started))) s")
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            debug(.default, "Background watchdog: run expired after \(Int(Date().timeIntervalSince(started))) s")
            complete(false)
        }

        // A background launch before the first unlock after a reboot cannot read the app's
        // files; startIfNeeded() defers in that case and there is nothing to check.
        AppLauncher.shared.startIfNeeded()
        guard let services = AppLauncher.shared.services else {
            debug(.default, "Background watchdog: app not started (protected data unavailable), nothing to check")
            complete(true)
            return
        }

        let now = Date()
        let latestReading = services.resolver.resolve(GlucoseStorage.self)?.latestDate()
        let readingAge = now.timeIntervalSince(latestReading ?? .distantPast)
        let loopAge = now.timeIntervalSince(services.apsManager.lastLoopDate)
        let state = UIApplication.shared.applicationState

        debug(
            .default,
            "Background watchdog: run (app \(state.description)), last reading \(readingAge.minutesDescription) ago, last loop \(loopAge.minutesDescription) ago"
        )
        FootprintLog.log("background watchdog")

        guard services.deviceManager.cgmManager != nil else {
            complete(true)
            return
        }
        guard readingAge > staleAfter else {
            complete(true)
            return
        }

        debug(.default, "Background watchdog: readings are stale, asking the CGM to reconnect and forcing a loop")
        services.deviceManager.backgroundWatchdogFired()

        if state != .active, notifiedForReadingAt != latestReading {
            notifiedForReadingAt = latestReading
            services.resolver.resolve(UserNotificationsManager.self)?
                .notifyBackgroundWatchdog(minutesWithoutGlucose: Int(readingAge / 60))
        }

        // Stay awake briefly so a reconnect started above can deliver a reading while the
        // process is guaranteed to be running.
        DispatchQueue.main.asyncAfter(deadline: .now() + recoveryWindow) {
            complete(true)
        }
    }
}

private extension TimeInterval {
    var minutesDescription: String {
        self > 10 * 365 * 24 * 3600 ? "never" : "\(Int(self / 60)) min"
    }
}

private extension UIApplication.State {
    var description: String {
        switch self {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}
