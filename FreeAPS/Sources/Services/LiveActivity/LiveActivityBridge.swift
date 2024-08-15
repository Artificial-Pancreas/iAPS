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

    init?(new bg: Readings?, prev: Readings?, mmol: Bool, suggestion: Suggestion, loopDate: Date) {
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

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg?.date ?? Date.now,
            iob: iobString,
            cob: cobString,
            loopDate: loopDate,
            eventual: eventual,
            mmol: mmol
        )
    }
}

@available(iOS 16.2, *) private struct ActiveActivity {
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

@available(iOS 16.2, *) final class LiveActivityBridge: Injectable, ObservableObject {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

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

        monitorForLiveActivityAuthorizationChanges()
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
    private func forceActivityUpdate() {
        // just before app resigns active, show a new activity
        // only do this if there is no current activity or the current activity is older than 1h
        if settings.useLiveActivity {
            if currentActivity?.needsRecreation() ?? true,
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
                let content = ActivityContent(
                    state: state,
                    staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(8 * 60))
                )

                await currentActivity.activity.update(content)
            }
        } else {
            do {
                // always push a non-stale content as the first update
                // pushing a stale content as the first content results in the activity not being shown at all
                // we want it shown though even if it is iniially stale, as we expect new BG readings to become available soon, which should then be displayed
                let nonStale = ActivityContent(
                    state: LiveActivityAttributes.ContentState(
                        bg: "--",
                        direction: nil,
                        change: "--",
                        date: Date.now,
                        iob: "--",
                        cob: "--",
                        loopDate: Date.now, eventual: "--", mmol: false
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

@available(iOS 16.2, *)
extension LiveActivityBridge: SuggestionObserver, EnactedSuggestionObserver {
    func enactedSuggestionDidUpdate(_ suggestion: Suggestion) {
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
        let glucose = cd.fetchGlucose(interval: DateFilter().twoHours)
        let prev = glucose.count > 1 ? glucose[1] : glucose.first

        guard let content = LiveActivityAttributes.ContentState(
            new: glucose.first,
            prev: prev,
            mmol: settings.units == .mmolL,
            suggestion: suggestion,
            loopDate: (suggestion.recieved ?? false) ? (suggestion.timestamp ?? .distantPast) :
                (cd.fetchLastLoop()?.timestamp ?? .distantPast)
        ) else {
            return
        }

        Task {
            await self.pushUpdate(content)
        }
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
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
        let glucose = cd.fetchGlucose(interval: DateFilter().twoHours)
        let prev = glucose.count > 1 ? glucose[1] : glucose.first

        guard let content = LiveActivityAttributes.ContentState(
            new: glucose.first,
            prev: prev,
            mmol: settings.units == .mmolL,
            suggestion: suggestion,
            loopDate: settings.closedLoop ? (cd.fetchLastLoop()?.timestamp ?? .distantPast) : suggestion.timestamp ?? .distantPast
        ) else {
            return
        }

        Task {
            await self.pushUpdate(content)
        }
    }
}
