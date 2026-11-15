import Combine
import Foundation
import SwiftUI
import UIKit

extension LoopHistory {
    /// The Loops screen's state: the last read (`HomeLoopsStore.History`) and the day picked, formatted (`Content`).
    ///
    /// Data-driven, no clock, as the Home Loops card: read when it comes up, then on a loop (`latestLoopOutcome`: the
    /// readings before it too), on the readings changing while no loop comes (`glucoseStatsChanged`, only for the
    /// ongoing gap, `HomeLoopsCard.Content.readingMayChange`), on a change of the 1-minute loop, at midnight and DST
    /// (`significantTimeChange`), and back from the background. While it is not on screen (or in the background) those
    /// mark it stale; coming up reads. A pick reads nothing: the content is made again from the last read.
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner, UIBindingOwner {
        let uiBindings = UIBindings()

        /// nil until the first read (a failed one keeps the last)
        @Published private(set) var content: Content?
        /// the first read failed: nothing to show
        @Published private(set) var failed = false

        private var selection: Selection = .lastDays
        private var history: HomeLoopsStore.History?
        /// the 1-minute loop, from the settings; nil until they are delivered
        private var config: Home.LoopsConfig?
        /// the read in flight: at most one, plus `pending`
        private var task: Task<Void, Never>?
        private var pending = false
        /// on screen (between appear and disappear)
        private var isShown = false
        /// a read was asked for while not on screen, or in the background: coming up (or back) reads
        private var stale = true
        private var inBackground = false
        /// a failed read's retry, in a minute
        private var retry: Task<Void, Never>?

        override func subscribe() async {
            observeUI(appCoordinator.settings, map: { Home.LoopsConfig($0) }) { me, config in
                me.configChanged(config)
            }
            observeUI(appCoordinator.latestLoopOutcome, dropInitial: true) { me, outcome in
                guard outcome != nil else { return }
                me.refresh()
            }
            observeUI(appCoordinator.glucoseStatsChanged, dropInitial: true) { me, _ in
                me.readingsChanged()
            }
            // midnight, DST, a time zone change
            observe(notification: UIApplication.significantTimeChangeNotification) { me in
                await me.refresh()
            }
            observe(notification: UIApplication.didEnterBackgroundNotification) { me in
                await me.enteredBackground()
            }
            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.becameActive()
            }
        }

        // MARK: - Screen

        func appear() {
            isShown = true
            if stale {
                refresh()
            }
        }

        func disappear() {
            isShown = false
            // a failed read's retry is dropped: coming up reads again
            if retry != nil {
                stale = true
            }
            cancelRetry()
        }

        /// A day of the calendar, or the 30 days again (the same day again too).
        func select(_ selection: Selection) {
            self.selection = selection == self.selection ? .lastDays : selection
            rebuild()
        }

        func showLastDays() {
            selection = .lastDays
            rebuild()
        }

        // MARK: - Triggers

        private func configChanged(_ config: Home.LoopsConfig) {
            guard config != self.config else { return }
            self.config = config
            refresh()
        }

        /// The readings changed: the next loop reads them, so read now only when they can change the screen before it,
        /// the ongoing gap, or without a result.
        private func readingsChanged() {
            guard history == nil
                || HomeLoopsCard.Content.readingMayChange(newestStart: newestStart, now: Date())
            else { return }
            refresh()
        }

        /// the newest loop start of the last read
        private var newestStart: Date? {
            guard let history else { return nil }
            return history.days.last { $0.lastStart != nil }?.lastStart ?? history.previousStart
        }

        private func enteredBackground() {
            // the notification comes asynchronously: nothing to do when the app is back already
            guard UIApplication.shared.applicationState == .background else { return }
            inBackground = true
            cancelRetry()
        }

        /// Only back from the background: the data and the time went on meanwhile.
        private func becameActive() {
            guard inBackground else { return }
            inBackground = false
            stale = true
            if isShown {
                refresh()
            }
        }

        // MARK: - Reads

        /// Reads at once, after the read in flight (once), or, not on screen or in the background, when it comes up.
        func refresh() {
            guard config != nil else { return }
            cancelRetry()
            guard isShown, !inBackground, UIApplication.shared.applicationState != .background else {
                stale = true
                return
            }
            stale = false
            guard task == nil else {
                pending = true
                return
            }
            start()
        }

        private func start() {
            guard let config else { return }
            pending = false
            let provider = self.provider
            task = Task { [weak self] in
                let history = await provider.history(allowOneMinuteLoop: config.allowOneMinuteLoop)
                guard let self else { return }
                self.task = nil
                // a newer request replaces this result at once
                guard !self.pending else {
                    self.refresh()
                    return
                }
                guard config == self.config else { return }
                guard let history else {
                    if self.content == nil {
                        self.failed = true
                    }
                    self.scheduleRetry()
                    return
                }
                self.failed = false
                self.history = history
                self.rebuild()
            }
        }

        /// The content from the last read and the selection; a day the read no longer has is the 30 days again.
        private func rebuild() {
            guard let history else { return }
            let content = Content.make(history, selection: selection, calendar: .current)
            selection = content.selection
            if content != self.content {
                self.content = content
            }
        }

        private func cancelRetry() {
            retry?.cancel()
            retry = nil
        }

        /// A failed read's retry, a minute after it, while on screen (any other read first cancels it).
        private func scheduleRetry() {
            cancelRetry()
            guard isShown, UIApplication.shared.applicationState != .background else {
                stale = true
                return
            }
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TimeInterval.minutes(1)))
                guard !Task.isCancelled else { return }
                self?.retry = nil
                self?.refresh()
            }
        }
    }
}
