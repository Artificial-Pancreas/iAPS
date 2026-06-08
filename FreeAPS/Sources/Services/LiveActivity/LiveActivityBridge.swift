import ActivityKit
import Foundation
import Swinject
import UIKit

extension LiveActivityAttributes.ContentState {
    static func formatGlucose(_ value: Int, mmol: Bool, forceSign: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if mmol {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        if forceSign {
            formatter.positivePrefix = formatter.plusSign
        }
        formatter.roundingMode = .halfUp

        return formatter
            .string(from: mmol ? value.asMmolL as NSNumber : NSNumber(value: value)) ?? ""
    }

    static func formatter(_ string: NSNumber) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: string) ?? ""
    }

    static func carbFormatter(_ string: NSNumber) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: string) ?? ""
    }

    init?(
        new bg: Readings?,
        prev: Readings?,
        mmol: Bool,
        suggestion: Suggestion,
        iob: Decimal?,
        loopDate: Date,
        readings: [Readings]?,
        predictions: Predictions?,
        showChart: Bool,
        watchChart: Bool,
        watchPredictions: Bool,
        watchDelta: Bool,
        watchEventual: Bool,
        chartLowThreshold: Int,
        chartHighThreshold: Int
    ) {
        guard let glucose = bg?.glucose else {
            return nil
        }

        let formattedBG = Self.formatGlucose(Int(glucose), mmol: mmol, forceSign: false)
        let trendString = bg?.direction
        let change = Self.formatGlucose(Int((bg?.glucose ?? 0) - (prev?.glucose ?? 0)), mmol: mmol, forceSign: true)
        let cobString = Self.carbFormatter((suggestion.cob ?? 0) as NSNumber)
        let iobString = Self.formatter((iob ?? 0) as NSNumber)
        let eventual = Self.formatGlucose(suggestion.eventualBG ?? 100, mmol: mmol, forceSign: false)

        let activityPredictions: LiveActivityAttributes.ActivityPredictions?
        if let predictions = predictions, let bgDate = bg?.date {
            func createPoints(from values: [Int]?) -> LiveActivityAttributes.ValueSeries? {
                let prefixToTake = 24
                if let values = values {
                    let dates = values.dropFirst().indices.prefix(prefixToTake).map {
                        bgDate.addingTimeInterval(TimeInterval($0 * 5 * 60))
                    }
                    let clampedValues = values.dropFirst().prefix(prefixToTake).map { Int16(clamping: $0) }
                    return LiveActivityAttributes.ValueSeries(dates: dates, values: clampedValues)
                } else {
                    return nil
                }
            }

            let converted = LiveActivityAttributes.ActivityPredictions(
                iob: createPoints(from: predictions.iob),
                zt: createPoints(from: predictions.zt),
                cob: createPoints(from: predictions.cob),
                uam: createPoints(from: predictions.uam)
            )
            activityPredictions = converted
        } else {
            activityPredictions = nil
        }

        let preparedReadings: LiveActivityAttributes.ValueSeries? = {
            guard let readings else { return nil }
            let validReadings = readings.compactMap { reading -> (Date, Int16)? in
                guard let date = reading.date else { return nil }
                return (date, reading.glucose)
            }

            let dates = validReadings.map(\.0)
            let values = validReadings.map(\.1)

            return LiveActivityAttributes.ValueSeries(dates: dates, values: values)
        }()

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg?.date ?? Date.now,
            iob: iobString,
            cob: cobString,
            loopDate: loopDate,
            eventual: eventual,
            mmol: mmol,
            readings: preparedReadings,
            predictions: activityPredictions,
            showChart: showChart,
            watchChart: watchChart,
            watchPredictions: watchPredictions,
            watchDelta: watchDelta,
            watchEventual: watchEventual,
            chartLowThreshold: Int16(clamping: chartLowThreshold),
            chartHighThreshold: Int16(clamping: chartHighThreshold)
        )
    }
}

private struct ActiveActivity {
    let activity: Activity<LiveActivityAttributes>
    let startDate: Date

    func needsRecreation() -> Bool {
        switch activity.activityState {
        case .dismissed,
             .ended,
             .stale:
            return true
        case .active,
             .pending:
            break
        @unknown default:
            break
        }

        return -startDate.timeIntervalSinceNow >
            TimeInterval(60 * 60)
    }
}

actor LiveActivityBridge: Sendable, LifetimeOwner, AppService {
    private let settingsManager: SettingsManager
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    private let coreDataStorage = CoreDataStorage()

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()

    private var systemEnabled: Bool = false

    let lifetime = Lifetime()

    private var knownSettings: FreeAPSSettings?

    private var currentActivity: ActiveActivity?
    private var suggestion: Suggestion?
    private var enactedSuggestion: Suggestion?
    private var iob: IOBTick0?

    init(
        settingsManager: SettingsManager,
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.settingsManager = settingsManager
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called at the start of the app
    func start() async {
        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled
        appCoordinator.setLiveActivitiesSystemEnabled(systemEnabled)

        let settings = appCoordinator.settings.value
        knownSettings = settings

        suggestion = await storage.retrieveFile(OpenAPS.Enact.suggested, as: Suggestion.self)
        enactedSuggestion = await storage.retrieveFile(OpenAPS.Enact.enacted, as: Suggestion.self)
        iob = coreDataStorage.fetchLatestInsulinData()

        observe(appCoordinator.enactedSuggestions) { me, enactedSuggestion in
            await me.newEnactedSuggestion(enactedSuggestion)
        }
        observe(appCoordinator.suggestions) { me, suggestion in
            await me.newSuggestion(suggestion)
        }
        observe(appCoordinator.pumpHistoryUpdates) { me, pumpHistory in
            await me.pumpHistoryUpdated(pumpHistory)
        }
        observe(appCoordinator.settings) { me, newSettings in
            await me.settingsUpdated(newSettings)
        }
        observe(notification: UIApplication.didEnterBackgroundNotification) { me in
            await me.forceActivityUpdate()
        }
        observe(notification: UIApplication.didBecomeActiveNotification) { me in
            await me.forceActivityUpdate()
        }

        // cannot use observe here because ActivityKit's `ActivityEnablementUpdates` isn't Sendable
        Task {
            for await activityState in activityAuthorizationInfo.activityEnablementUpdates {
                if activityState != systemEnabled {
                    systemEnabled = activityState
                    appCoordinator.setLiveActivitiesSystemEnabled(systemEnabled)
                    if systemEnabled {
                        await self.forceActivityUpdate(force: true)
                    } else {
                        currentActivity = nil
                    }
                }
            }
        }.store(in: lifetime)
    }

    private func newEnactedSuggestion(_ enactedSuggestion: Suggestion) async {
        self.enactedSuggestion = enactedSuggestion
        await updateActivityContent()
    }

    private func newSuggestion(_ suggestion: Suggestion) async {
        self.suggestion = suggestion
        await updateActivityContent()
    }

    private func pumpHistoryUpdated(_: [PumpHistoryEvent]) async {
        iob = coreDataStorage.fetchLatestInsulinData()
        await updateActivityContent()
    }

    private func settingsUpdated(_ newSettings: FreeAPSSettings) async {
        let oldSettings = knownSettings
        knownSettings = newSettings
        if let oldSettings {
            if newSettings.useLiveActivity != oldSettings.useLiveActivity ||
                newSettings.liveActivityChart != oldSettings.liveActivityChart ||
                newSettings.liveActivityChartShowPredictions != oldSettings.liveActivityChartShowPredictions ||
                newSettings.liveActivityWatchChart != oldSettings.liveActivityWatchChart ||
                newSettings.liveActivityWatchPredictions != oldSettings.liveActivityWatchPredictions ||
                newSettings.liveActivityWatchDelta != oldSettings.liveActivityWatchDelta
            {
                print("live activity settings changed")
                await forceActivityUpdate(force: true)
            }
        }
    }

    /// creates and tries to present a new activity update from the current Suggestion values if live activities are enabled in settings
    /// Ends existing live activities if live activities are not enabled in settings
    private func forceActivityUpdate(force: Bool = false) async {
        guard let knownSettings, systemEnabled else { return }
        // just before app resigns active, show a new activity
        // only do this if there is no current activity or the current activity is older than 1h
        if knownSettings.useLiveActivity {
            if force || currentActivity?.needsRecreation() ?? true {
                await updateActivityContent()
            }
        } else {
            await endActivity()
        }
    }

    private func updateActivityContent() async {
        guard let settings = knownSettings, systemEnabled else { return }

        guard settings.useLiveActivity else {
            if currentActivity != nil {
                await endActivity()
            }
            return
        }

        let theSuggestion: Suggestion
        let loopDate: Date
        var iobValue: Decimal?

        // TODO: this check should be like this instead:
        // IF enactedSuggestion AND ((NOT suggestion) OR (suggestion is older than enactedSuggestion))
        if let enactedSuggestion {
            theSuggestion = enactedSuggestion
            iobValue = enactedSuggestion.iob
            if enactedSuggestion.recieved ?? false {
                loopDate = enactedSuggestion.timestamp ?? .distantPast
            } else {
                loopDate = coreDataStorage.fetchLastLoop()?.timestamp ?? .distantPast
            }
        } else if let suggestion {
            theSuggestion = suggestion
            iobValue = suggestion.iob
            if settings.closedLoop {
                loopDate = coreDataStorage.fetchLastLoop()?.timestamp ?? .distantPast
            } else {
                loopDate = suggestion.timestamp ?? .distantPast
            }
        } else {
            return
        }

        if let iob, iobValue == nil || iob.time > loopDate {
            iobValue = iob.iob
        }

        guard let content = Self.buildContentState(
            settings: settings,
            suggestion: theSuggestion,
            iob: iobValue,
            loopDate: loopDate,
            glucose: coreDataStorage.fetchGlucose(interval: DateFilter.threeHours.startDate)
        ) else {
            return
        }
        await pushUpdate(content, settings: settings)
    }

    /// attempts to present this live activity state, creating a new activity if none exists yet
    private func pushUpdate(_ state: LiveActivityAttributes.ContentState, settings: FreeAPSSettings) async {
        guard systemEnabled else { return }

        // hide duplicate/unknown activities
        for unknownActivity in Activity<LiveActivityAttributes>.activities {
            guard unknownActivity.id != currentActivity?.activity.id else { continue }
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        if let currentActivity {
            if currentActivity.needsRecreation(), await UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
                await endActivity()
                await pushUpdate(state, settings: settings)
            } else {
                let encoder = JSONEncoder()
                let encodedLength: Int = {
                    if let data = try? encoder.encode(state) {
                        return data.count
                    } else {
                        return 0
                    }
                }()

                let content = {
                    if encodedLength > 4 * 1024 { // size limit
                        debug(
                            .service,
                            "live activity payload maximum size exceeded: \(encodedLength) bytes, updating live activity without predictions"
                        )
                        return ActivityContent(
                            state: state.withoutPredictions(),
                            staleDate: Date.now.addingTimeInterval(TimeInterval(12 * 60))
                        )
                    } else {
                        return ActivityContent(
                            state: state,
                            staleDate: Date.now.addingTimeInterval(TimeInterval(12 * 60))
                        )
                    }
                }()

                await currentActivity.activity.update(content)
            }
        } else {
            do {
                // always push a non-stale content as the first update
                // pushing a stale content as the first content results in the activity not being shown at all
                // we want it shown though even if it is initially stale, as we expect new BG readings to become available soon, which should then be displayed
                let nonStale = ActivityContent(
                    state: LiveActivityAttributes.ContentState(
                        bg: "--",
                        direction: nil,
                        change: "--",
                        date: Date.now,
                        iob: "--",
                        cob: "--",
                        loopDate: Date.now, eventual: "--", mmol: false,
                        readings: nil,
                        predictions: nil,
                        showChart: settings.liveActivityChart,
                        watchChart: settings.liveActivityWatchChart,
                        watchPredictions: settings.liveActivityWatchPredictions,
                        watchDelta: settings.liveActivityWatchDelta,
                        watchEventual: settings.liveActivityWatchEventual,
                        chartLowThreshold: Int16(clamping: (settings.low as NSDecimalNumber).intValue),
                        chartHighThreshold: Int16(clamping: (settings.high as NSDecimalNumber).intValue)
                    ),
                    staleDate: Date.now.addingTimeInterval(60)
                )

                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: nonStale,
                    pushType: nil
                )

                currentActivity = ActiveActivity(activity: activity, startDate: Date.now)

                // then show the actual content
                await pushUpdate(state, settings: settings)
            } catch {
                debug(.service, "activity creation error: \(error)")
            }
        }
    }

    /// ends all live activities immediately
    private func endActivity() async {
        if let currentActivity {
            await currentActivity.activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }

        // end any other activities
        for unknownActivity in Activity<LiveActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

extension LiveActivityBridge {
    private static func buildContentState(
        settings: FreeAPSSettings,
        suggestion: Suggestion,
        iob: Decimal?,
        loopDate: Date,
        glucose: [Readings]
    ) -> LiveActivityAttributes.ContentState? {
        let previousGlucose = glucose.count > 1 ? glucose[1] : glucose.first

        return LiveActivityAttributes.ContentState(
            new: glucose.first,
            prev: previousGlucose,
            mmol: settings.units == .mmolL,
            suggestion: suggestion,
            iob: iob,
            loopDate: loopDate,
            readings: settings.liveActivityChart ? glucose : nil,
            predictions: settings.liveActivityChart && settings.liveActivityChartShowPredictions ? suggestion.predictions : nil,
            showChart: settings.liveActivityChart,
            watchChart: settings.liveActivityWatchChart,
            watchPredictions: settings.liveActivityWatchPredictions,
            watchDelta: settings.liveActivityWatchDelta,
            watchEventual: settings.liveActivityWatchEventual,
            chartLowThreshold: Int(settings.low),
            chartHighThreshold: Int(settings.high)
        )
    }
}
