import Foundation
import Swinject

/// The Loops screen, opened by the Home Loops card: the last five weeks day by day (a heat-map of the share of the
/// loops due that ran), and the detail of the last 30 days or of the day picked: the share, the failed and missed
/// loops, the median loop, the strip through the day, the longest gaps, why loops failed. The same numbers as the
/// card (`HomeLoopStats`, per slot), from the same store (`HomeLoopsStore`, the days cached).
enum LoopHistory {
    enum Config {
        /// the detail without a day picked: the last 30 days, today's part included
        static let aggregateDays = 30
        /// the calendar's weeks, this one last
        static let weeks = 5
        /// the longest gaps listed
        static let gapsShown = 3
        /// the failure causes listed, the rest as one "Other" ("No loop ran" is a row of its own)
        static let causesShown = 5
    }

    /// What the detail shows.
    enum Selection: Hashable, Sendable {
        /// the last `Config.aggregateDays` days
        case lastDays
        /// a day, by its start
        case day(Date)
    }
}

protocol LoopHistoryProvider: Provider {
    /// The last `HomeLoopsStore.Config.historyDays` days up to now; nil when they couldn't be read.
    func history(allowOneMinuteLoop: Bool) async -> HomeLoopsStore.History?
}

extension LoopHistory {
    final class Provider: LoopHistoryProvider, Sendable {
        /// shared with the Home Loops card
        private let loops: HomeLoopsStore

        required init(resolver: Resolver) {
            loops = resolver.resolve(HomeLoopsStore.self)!
        }

        /// Read and computed off the main actor, the complete days from the store's cache.
        func history(allowOneMinuteLoop: Bool) async -> HomeLoopsStore.History? {
            await loops.history(allowOneMinuteLoop: allowOneMinuteLoop, now: Date(), calendar: .current)
        }
    }
}
