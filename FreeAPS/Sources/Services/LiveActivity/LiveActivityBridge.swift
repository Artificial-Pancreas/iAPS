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
        loopDate: Date,
        readings: [Readings]?,
        predictions: Predictions?,
        showChart: Bool,
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
        let iobString = Self.formatter((suggestion.iob ?? 0) as NSNumber)
        let eventual = Self.formatGlucose(suggestion.eventualBG ?? 100, mmol: mmol, forceSign: false)
        let mmol = mmol

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
        case .active: break
        @unknown default:
            return true
        }

        return -startDate.timeIntervalSinceNow >
            TimeInterval(60 * 60)
    }
}

final class LiveActivityBridge: Injectable, ObservableObject, SettingsObserver {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    private let coreDataStorage = CoreDataStorage()

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

    private var knownSettings: FreeAPSSettings?

    private var currentActivity: ActiveActivity?
    private var latestGlucose: Readings?
    private var loopDate: Date?
    private var suggestion: Suggestion?

    init(resolver: Resolver) {
        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled

        injectServices(resolver)
        broadcaster.register(SuggestionObserver.self, observer: self)
        broadcaster.register(EnactedSuggestionObserver.self, observer: self)

        Foundation.NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            self.forceActivityUpdate()
        }

        Foundation.NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { _ in
            self.forceActivityUpdate()
        }

        knownSettings = settings
        broadcaster.register(SettingsObserver.self, observer: self)

        monitorForLiveActivityAuthorizationChanges()
    }

    func settingsDidChange(_ newSettings: FreeAPSSettings) {
        if let knownSettings = self.knownSettings {
            if newSettings.useLiveActivity != knownSettings.useLiveActivity ||
                newSettings.liveActivityChart != knownSettings.liveActivityChart ||
                newSettings.liveActivityChartShowPredictions != knownSettings.liveActivityChartShowPredictions
            {
                print("live activity settings changed")
                forceActivityUpdate(force: true)
            } else {
                print("live activity settings unchanged")
            }
        }
        knownSettings = newSettings
    }

    private func monitorForLiveActivityAuthorizationChanges() {
        Task {
            for await activityState in activityAuthorizationInfo.activityEnablementUpdates {
                if activityState != systemEnabled {
                    await MainActor.run {
                        systemEnabled = activityState
                    }
                }
            }
        }
    }

    /// creates and tries to present a new activity update from the current Suggestion values if live activities are enabled in settings
    /// Ends existing live activities if live activities are not enabled in settings
    private func forceActivityUpdate(force: Bool = false) {
        // just before app resigns active, show a new activity
        // only do this if there is no current activity or the current activity is older than 1h
        if settings.useLiveActivity {
            if force || currentActivity?.needsRecreation() ?? true,
               let suggestion = storage.retrieveFile(OpenAPS.Enact.suggested, as: Suggestion.self)
            {
                suggestionDidUpdate(suggestion)
            }
        } else {
            Task {
                await self.endActivity()
            }
        }
    }

    /// attempts to present this live activity state, creating a new activity if none exists yet
    @MainActor private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
        // hide duplicate/unknown activities
        for unknownActivity in Activity<LiveActivityAttributes>.activities
            .filter({ self.currentActivity?.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        if let currentActivity {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
                await endActivity()
                await pushUpdate(state)
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
                        print(
                            "live activity payload maximum size exceeded: \(encodedLength) bytes, updating live activity without predictions"
                        )
                        return ActivityContent(
                            state: state.withoutPredictions(),
                            staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(12 * 60))
                        )
                    } else {
                        return ActivityContent(
                            state: state,
                            staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(12 * 60))
                        )
                    }
                }()

                await currentActivity.activity.update(content)
            }
        } else {
            do {
                // always push a non-stale content as the first update
                // pushing a stale content as the first content results in the activity not being shown at all
                // we want it shown though even if it is iniially stale, as we expect new BG readings to become available soon, which should then be displayed
                let settings = self.settings
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
                await pushUpdate(state)
            } catch {
                print("activity creation error: \(error)")
            }
        }
    }

    /// ends all live activities immediateny
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

extension LiveActivityBridge: SuggestionObserver, EnactedSuggestionObserver {
    func enactedSuggestionDidUpdate(_ suggestion: Suggestion) {
        let settings = self.settings

        guard settings.useLiveActivity else {
            if currentActivity != nil {
                Task {
                    await self.endActivity()
                }
            }
            return
        }
        defer { self.suggestion = suggestion }

        let cd = CoreDataStorage()
        let glucose = cd.fetchGlucose(interval: DateFilter().threeHours)
        let prev = glucose.count > 1 ? glucose[1] : glucose.first

        guard let content = LiveActivityAttributes.ContentState(
            new: glucose.first,
            prev: prev,
            mmol: settings.units == .mmolL,
            suggestion: suggestion,
            loopDate: (suggestion.recieved ?? false) ? (suggestion.timestamp ?? .distantPast) :
                (cd.fetchLastLoop()?.timestamp ?? .distantPast),
            readings: settings.liveActivityChart ? glucose : nil,
            predictions: settings.liveActivityChart && settings.liveActivityChartShowPredictions ? suggestion.predictions : nil,
            showChart: settings.liveActivityChart,
            chartLowThreshold: Int(settings.low),
            chartHighThreshold: Int(settings.high)
        ) else {
            return
        }

        Task {
            await self.pushUpdate(content)
        }
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        let settings = self.settings

        guard settings.useLiveActivity else {
            if currentActivity != nil {
                Task {
                    await self.endActivity()
                }
            }
            return
        }
        defer { self.suggestion = suggestion }

        let cd = CoreDataStorage()
        let glucose = cd.fetchGlucose(interval: DateFilter().threeHours)
        let prev = glucose.count > 1 ? glucose[1] : glucose.first

        guard let content = LiveActivityAttributes.ContentState(
            new: glucose.first,
            prev: prev,
            mmol: settings.units == .mmolL,
            suggestion: suggestion,
            loopDate: settings.closedLoop ? (cd.fetchLastLoop()?.timestamp ?? .distantPast) : suggestion
                .timestamp ?? .distantPast,
            readings: settings.liveActivityChart ? glucose : nil,
            predictions: settings.liveActivityChart && settings.liveActivityChartShowPredictions ? suggestion.predictions : nil,
            showChart: settings.liveActivityChart,
            chartLowThreshold: Int(settings.low),
            chartHighThreshold: Int(settings.high)
        ) else {
            return
        }

        Task {
            await self.pushUpdate(content)
        }
    }
}
