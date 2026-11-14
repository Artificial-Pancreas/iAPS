import Combine
import Foundation
import SwiftUI
import Swinject
import UIKit

extension Stat {
    /// What a glucose view shows, one case per view.
    enum GlucoseContent: Equatable {
        case overview(Overview)
        case trace(Trace)
        case agp(AGP)
        case goodBadDays(GoodBadDays)
        case daily(Daily)
        case hourOfDay(HourOfDay)
        case weekday(Weekday)
        case weekly(Weekly)

        var tab: StatsTab {
            switch self {
            case .overview: return .overview
            case .trace: return .trace
            case .agp: return .agp
            case .goodBadDays: return .goodBadDays
            case .daily: return .daily
            case .hourOfDay: return .hourOfDay
            case .weekday: return .weekday
            case .weekly: return .weekly
            }
        }
    }

    final class StateModel: BaseStateModel<Provider>, UIBindingOwner {
        let uiBindings = UIBindings()

        /// the view shown (the title menu's pick, `StatsViewMenu`)
        @Published private(set) var tab: StatsTab

        /// the user's last explicit pick; `period` is the nearest one the current tab offers
        @Published private(set) var preferredPeriod: StatsPeriod
        /// By weekday's whole weeks (`StatsPeriod.weekdayPeriods`), a period of its own: picking one leaves the preferred
        /// period (the other views') as it is. 8 weeks every time Statistics opens, kept while it is open
        @Published private(set) var weekdayPeriod: StatsPeriod = .weeks8
        /// Good & bad days' 14, 30 or 90 days (`StatsPeriod.usualDayPeriods`), a period of its own as By weekday's:
        /// `goodBadDaysOpeningPeriod` every time Statistics opens, kept while it is open
        @Published private(set) var goodBadDaysPeriod: StatsPeriod = Stat.StateModel.goodBadDaysOpeningPeriod
        @Published private(set) var glucoseContent: ViewContent<GlucoseContent> = .loading(previous: nil)
        @Published private(set) var insulinContent: ViewContent<Insulin> = .loading(previous: nil)
        @Published private(set) var mealsContent: ViewContent<Meals> = .loading(previous: nil)
        @Published private(set) var patchesContent: ViewContent<Patches> = .loading(previous: nil)
        /// the CGM topic's three views, formatted for `cgmPick` from `cgmResult`
        @Published private(set) var cgmContent: ViewContent<CGMReport> = .loading(previous: nil)
        /// the CGM picked in the CGM topic's picker, kept while Statistics is open; nil (every time it opens), or one a
        /// period lacks: the CGM with the newest reading (`CGMResult.shown`)
        @Published private(set) var cgmPick: CGMPick?
        /// The Patches topic's naming (Patches, Pods or Sites); nil without a pump session in the last 120 days: the
        /// title menu has no Patches item. Loaded on its own (`loadPatchTopic`) when the screen comes up on another tab, and with every
        /// Patches read.
        @Published private(set) var patchTopic: PatchTopic?
        @Published private(set) var settings = StatsSettings(FreeAPSSettings())
        /// the day picked on the Day tab (`.today` follows midnight); `traceShownDay` keeps a past one inside the
        /// selector's days
        @Published private(set) var traceDay: TraceDay = .today
        /// The Day tab's selector, loaded on its own (`loadTraceSelector`): a trace never waits for its 90 days, and a
        /// day picked neither waits for nor cancels them. Kept as it is when a reload gives the same items.
        @Published private(set) var traceSelector: [TraceSelectorItem] = []
        /// The Day tab's usual day: shown or not (off by default) and its baseline, the last 14 / 30 / 90 days ending
        /// today (`StatsPeriod.usualDayPeriods`), both kept across launches on the phone (`StatsDisplayPreferences`).
        /// Changed only through `showUsualDay` and `select(usualDayPeriod:)`, which (re)load it.
        @Published private(set) var usualDayShown: Bool
        @Published private(set) var usualDayPeriod: StatsPeriod
        /// the usual day's picks, on the phone (UI-only, not in the settings)
        private let displayPreferences: StatsDisplayPreferences
        /// The baseline, loaded on its own (`loadUsualDay`), like the selector: the same for every day stepped through,
        /// so a day picked neither reloads nor waits for it. nil while not shown, and until it comes in.
        @Published private(set) var usualDay: UsualDay?
        /// the baseline placed on the trace shown (`UsualDayOverlay`), when it is drawn: rebuilt when either changes
        @Published private(set) var usualDayOverlay: UsualDayOverlay?
        /// the bin picked on the AGP, kept across periods; observed only by the views showing it (not by the chart's
        /// marks). No request carries it: the result doesn't depend on it, so picking one never recomputes
        let agpSelection = AGPSelection()
        /// the day picked on the Daily view, nil for today (so it follows midnight), kept inside its 90 days where
        /// it is shown; observed only by the Daily view. No request carries it: the result has every one of the 90 days,
        /// so picking one never recomputes
        let dailySelection = DailySelection()
        /// the hour picked on By hour, kept across periods; observed only by the views showing it (not by the chart's
        /// marks). No request carries it: the result has every hour, so picking one never recomputes
        let hourSelection = HourSelection()
        /// the cell picked on By weekday's heatmap and its metric, kept across periods; observed only by the views showing
        /// them. No request carries them: the result has every cell and metric
        let weekdaySelection = WeekdaySelection()
        /// Good & bad days' time picked and the day lists open, kept while Statistics is open (a day opened on the Day
        /// tab and the menu back find them as they were); observed only by its views. No request carries them
        let goodBadDaysSelection = GoodBadDaysSelection()
        /// the day picked on the Insulin tab's day chart (7–90 d), nil for yesterday, the last complete day (today has
        /// the Today period); otherwise the Days tab's rules. Observed only by its views
        let insulinDaySelection = DailySelection(opensOnLastCompleteDay: true)
        /// the hour picked on the Insulin tab's by-hour charts (all of them show it, Today's too)
        let insulinHourSelection = HourSelection()
        /// the day picked on the Meals tab's day chart, nil for yesterday (as the Insulin tab's)
        let mealsDaySelection = DailySelection(opensOnLastCompleteDay: true)
        /// the hour picked on the Meals tab's by-time-of-day chart
        let mealsHourSelection = HourSelection()
        /// the day picked on a nutrient's day chart (pushed from the Nutrients screen), nil for yesterday; yesterday again
        /// when the Nutrients screen is opened, the same day across the nutrients
        let nutrientDaySelection = DailySelection(opensOnLastCompleteDay: true)
        /// the current `individualAdjustmentFactor`: the Meals tab's carb equivalents
        private var carbEquivalentFactor = 0.5
        /// the current sex and birth date (Settings › Sharing): the Nutrients screen's reference intakes
        private var nutrientDemographics = NutrientReferences.Demographics(sexSetting: 3, birthDate: .distantPast)
        /// the CGM topic's smoothing analyses, kept by key while Statistics is open; observed only by the Smoothing view
        let cgmSmoothing = CGMSmoothingRuns()
        /// the "Which CGM was this?" sheet's input and its writes (`CGMUnknownSheet`), reached through the report
        let cgmUnknownEditor = CGMUnknownEditor()
        /// the CGM topic's last result: a CGM picked is formatted from it, nothing is read
        private var cgmResult: CGMResult?
        /// the CGM topic's data generation (`CGMCacheKey.generation`): bumped by a readings change before the newest
        /// minutes (`cgmChangeInvalidates`), and by a read of content older than those minutes (`cgmContentIsStale`)
        private var cgmGeneration = 0
        /// the newest readings change when the CGM topic's content was read: a smoothing result that saw fewer is noted
        private var cgmReadingsSeq = 0

        /// what a computation was started for: its result is shown only while it still is what the screen shows
        private struct Request: Equatable, Sendable {
            let seq: Int
            let tab: StatsTab
            /// ignored by the Day tab (it has none; it never changes while it is shown)
            let period: StatsPeriod
            let settings: StatsSettings
            /// the Day tab's (`traceShownDay`), nil for the other tabs: `.today` across midnight stays current
            let traceDay: TraceDay?
        }

        /// the refresh in flight; its seq is the request's
        private let refreshes = StatsLatestTask()
        /// the refreshes started so far (each moves the seq on by one): the tests count them
        var refreshCount: Int { refreshes.seq }
        /// the start of the day of the last refresh's request, nil before the first: the first interaction after a
        /// midnight passed on screen reads again (`refreshIfDayMovedOn`), there being no clock to catch it
        private var lastRequestDay: Date?
        /// the screen sets the selections itself (`resetSelections`): no pick, a refresh follows
        private var resettingSelections = false
        private let traceSelectorLoads = StatsLatestTask()
        /// the start of today when the selector was last asked for: a refresh after midnight reloads it
        private var traceSelectorDay: Date?
        /// the usual day's loads: the current one, the day it was asked for, the readings changes it accounts for
        private let usualDayLoads = UsualDayLoads()
        /// from didEnterBackground to didBecomeActive: coming back refreshes what is shown
        private var inBackground = false
        /// the screen went down (`tearDown`) since it was last up: coming up again refreshes what is shown
        private var wentDown = false
        /// the Statistics pages on screen: the root, and the Meals tab's Nutrients pages pushed over it. A push or a pop
        /// shows the new one before or after the old one goes: the first in and the last out count (`StatsPageSet`)
        private let shownPages = StatsPageSet<Page>()
        /// non-nil while the service's session is open; nonisolated(unsafe) for the deinit only
        nonisolated(unsafe) private var sessionProvider: Stat.Provider?
        /// begin and end run one after the other, in order; nonisolated(unsafe) for the deinit only
        nonisolated(unsafe) private var sessionTask: Task<Void, Never>?

        /// - Parameter displayPreferences: the usual day's picks; tests pass their own `UserDefaults`
        init(
            resolver: Resolver,
            period: StatsPeriod,
            tab: StatsTab,
            displayPreferences: StatsDisplayPreferences = StatsDisplayPreferences()
        ) {
            preferredPeriod = period
            self.tab = tab
            self.displayPreferences = displayPreferences
            usualDayShown = displayPreferences.usualDayShown
            usualDayPeriod = displayPreferences.usualDayPeriod
            super.init(resolver: resolver)
            // opened on a tab: what entering it selects (`select(tab:)`; the onPick hooks below aren't wired yet, so
            // nothing reads); on the Day tab with 24 h (Home's On board card) the 24 hours instead of today
            selectEntering(tab)
            if tab == .trace, period == .last24h {
                traceDay = .last24h
            }
            // after the picks above: a pick on a chart, a stepper or a list reads nothing, unless midnight passed
            let picked: @MainActor() -> Void = { [weak self] in self?.selectionPicked() }
            agpSelection.onPick = picked
            hourSelection.onPick = picked
            weekdaySelection.onPick = picked
            goodBadDaysSelection.onPick = picked
            insulinHourSelection.onPick = picked
            mealsHourSelection.onPick = picked
            for selection in [dailySelection, insulinDaySelection, mealsDaySelection, nutrientDaySelection] {
                selection.onPick = picked
            }
            connectCGMUnknownEditor()
        }

        deinit {
            // gone without a disappear: close the session after the begin/end in flight, or the service never gets back to
            // no open sessions and keeps holding the readings
            guard let provider = sessionProvider else { return }
            Task.detached { [previous = sessionTask] in
                await previous?.value
                await provider.endSession()
            }
        }

        /// No live updates: what is shown is read when the screen opens (or comes up again), on a tab, period, day or
        /// settings change, and on coming back from the background, never with the data or the time alone (after a
        /// midnight passed on screen, any interaction reads: `refreshIfDayMovedOn`). The services' caches follow their
        /// own change signals, so the next read reads the changes.
        override func subscribe() async {
            settings = StatsSettings(appCoordinator.settings.value)
            // no refresh: the next Day tab refresh reloads the baseline when a readings change reached it
            observeUI(appCoordinator.glucoseStatsChanged, dropInitial: true) { me, change in
                me.usualDayLoads.noteChange(change, today: Self.startOfToday)
            }
            // no refresh either: the Patches topic's next read drops the kept sessions they touched. Not dropInitial: a
            // change between the read and the registration is noted (an older one returns early)
            patchChanges = PatchChangeLog(
                insulinSeq: appCoordinator.insulinStatsChanged.value.seq,
                glucoseSeq: appCoordinator.glucoseStatsChanged.value.seq
            )
            observeUI(appCoordinator.insulinStatsChanged, dropInitial: false) { me, change in
                me.patchChanges.noteInsulin(change)
            }
            observeUI(appCoordinator.glucoseStatsChanged, dropInitial: false) { me, change in
                me.patchChanges.noteGlucose(change)
            }
            // no refresh either: the CGM topic's next read computes it again
            observeUI(appCoordinator.glucoseStatsChanged, dropInitial: true) { me, change in
                if Self.cgmChangeInvalidates(change, now: Date()) {
                    me.cgmGeneration += 1
                }
            }
            // not dropInitial: a change between the read above and this registration is delivered (an unchanged
            // value returns early in settingsChanged)
            observeUI(appCoordinator.settings, map: { StatsSettings($0) }) { me, settings in
                me.settingsChanged(settings)
            }
            carbEquivalentFactor = (appCoordinator.settings.value.individualAdjustmentFactor as NSDecimalNumber).doubleValue
            // not dropInitial, as the settings above: an unchanged value returns early
            observeUI(
                appCoordinator.settings,
                map: { ($0.individualAdjustmentFactor as NSDecimalNumber).doubleValue }
            ) { me, factor in
                me.carbEquivalentFactorChanged(factor)
            }
            nutrientDemographics = NutrientReferences.Demographics(appCoordinator.settings.value)
            // not dropInitial, as the settings above: an unchanged value returns early
            observeUI(appCoordinator.settings, map: { NutrientReferences.Demographics($0) }) { me, demographics in
                me.nutrientDemographicsChanged(demographics)
            }
            refresh(showLoading: true)
            loadPatchTopicUnlessShown()
            observeForeground()
        }

        /// Coming back from the background (only then: Control Center or a system alert change nothing) refreshes what
        /// is shown, when it is on screen (otherwise its coming up does): the data and the time went on meanwhile, a
        /// midnight passed there too.
        private func observeForeground() {
            let center = Foundation.NotificationCenter.default
            center.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.inBackground = true } }
                .store(in: lifetime)
            center.publisher(for: UIApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.becameActive() } }
                .store(in: lifetime)
        }

        private func becameActive() {
            guard inBackground else { return }
            inBackground = false
            // the data went on meanwhile: the Patches topic's sessions are computed again (the CGM topic's when its
            // content is old, `cgmContentIsStale`)
            invalidatePatches()
            guard shownPages.isUp else { return }
            refresh(showLoading: false)
            loadPatchTopicUnlessShown()
        }

        /// The carb equivalents' factor: the Meals tab again (dimmed, as a settings change).
        private func carbEquivalentFactorChanged(_ factor: Double) {
            guard factor != carbEquivalentFactor else { return }
            carbEquivalentFactor = factor
            // down: coming up reads (`wentDown`)
            guard !wentDown, tab == .meals else { return }
            refresh(showLoading: true)
        }

        /// The sex or the birth date (the reference intakes): the Meals tab again (dimmed, as a settings change).
        private func nutrientDemographicsChanged(_ demographics: NutrientReferences.Demographics) {
            guard demographics != nutrientDemographics else { return }
            nutrientDemographics = demographics
            // down: coming up reads (`wentDown`)
            guard !wentDown, tab == .meals else { return }
            refresh(showLoading: true)
        }

        // MARK: - Selection

        var validPeriods: [StatsPeriod] {
            tab.validPeriods
        }

        /// the period shown: the preferred one, or the nearest one the current tab offers (the preferred one on the Day
        /// tab, which has none and ignores it; the only one on Weekly and "In range by day"); By weekday's and Good & bad
        /// days' own
        var period: StatsPeriod {
            Self.shownPeriod(on: tab, preferred: preferredPeriod, weekday: weekdayPeriod, goodBadDays: goodBadDaysPeriod)
        }

        /// Good & bad days' period when Statistics opens: 30 days, thirds of 10 days, recent enough to describe now.
        nonisolated static let goodBadDaysOpeningPeriod: StatsPeriod = .days30

        /// The period a tab shows: By weekday and Good & bad days their own (`weekdayPeriod`, `goodBadDaysPeriod`), the
        /// others the nearest one they offer to the preferred one.
        nonisolated static func shownPeriod(
            on tab: StatsTab,
            preferred: StatsPeriod,
            weekday: StatsPeriod,
            goodBadDays: StatsPeriod = Stat.StateModel.goodBadDaysOpeningPeriod
        ) -> StatsPeriod {
            switch tab {
            case .weekday: return nearest(weekday, in: tab.validPeriods)
            case .goodBadDays: return nearest(goodBadDays, in: tab.validPeriods)
            default: return nearest(preferred, in: tab.validPeriods)
            }
        }

        /// A period picked on a tab: on By weekday or Good & bad days its own period (one it offers), the preferred one
        /// left as it is; on the others the preferred one, the two own ones left as they are.
        nonisolated static func picking(
            _ period: StatsPeriod,
            on tab: StatsTab,
            preferred: StatsPeriod,
            weekday: StatsPeriod,
            goodBadDays: StatsPeriod = Stat.StateModel.goodBadDaysOpeningPeriod
        ) -> (preferred: StatsPeriod, weekday: StatsPeriod, goodBadDays: StatsPeriod) {
            func own(_ current: StatsPeriod) -> StatsPeriod {
                tab.validPeriods.contains(period) ? period : current
            }
            switch tab {
            case .weekday: return (preferred, own(weekday), goodBadDays)
            case .goodBadDays: return (preferred, weekday, own(goodBadDays))
            default: return (period, weekday, goodBadDays)
            }
        }

        /// A view picked (the title menu, `StatsViewMenu`); the view shown picked again reads again after a midnight.
        func select(tab: StatsTab) {
            guard tab != self.tab else {
                refreshIfDayMovedOn()
                return
            }
            self.tab = tab
            resetSelections { selectEntering(tab) }
            refresh(showLoading: true)
        }

        /// What entering a tab selects.
        private func selectEntering(_ tab: StatsTab) {
            switch tab {
            case .trace:
                // entering the Day tab selects today
                traceDay = .today
            case .agp:
                // entering the AGP selects the current clock time
                agpSelection.select(
                    GlucoseStatsEngine.agpBin(of: Date(), calendar: .current, binCount: AGPSelection.binCount)
                )
            case .daily:
                // entering the Days tab selects today
                dailySelection.select(nil)
            case .hourOfDay:
                // entering By hour selects the current clock hour
                hourSelection.select(Self.currentClockHour)
            case .weekday:
                // entering By weekday selects no cell (no detail); the metric stays
                weekdaySelection.clear()
            case .goodBadDays:
                // nothing: back from a day opened on the Day tab, the time and the open lists are as they were
                break
            case .insulin:
                // as the Days tab and By hour: the day it opens on (yesterday: today is the Today period's) and the
                // current clock hour
                insulinDaySelection.select(nil)
                insulinHourSelection.select(Self.currentClockHour)
            case .meals:
                mealsDaySelection.select(nil)
                mealsHourSelection.select(Self.currentClockHour)
            case .cgmOverview,
                 .cgmSensors,
                 .cgmSmoothing,
                 .overview,
                 .patches,
                 .weekly: break
            }
        }

        /// "Show Today" on the selected day's card (today's column picked on 7–90 d): the Today period; the days open on
        /// yesterday again when one of 7–90 d is picked next.
        func showToday() {
            resetSelections {
                Self.resetDays(
                    showingTodayOn: tab,
                    insulin: insulinDaySelection,
                    meals: mealsDaySelection,
                    nutrient: nutrientDaySelection
                )
            }
            select(period: .today)
        }

        /// "Show Today"'s resets: the tab's day selections back to the day they open on (nil, yesterday), so 7–90 d
        /// picked after Today show yesterday, not today's column again; the Meals tab's nutrients' too (their screen is
        /// pushed over it). A period picked in the control instead keeps the day picked, as on every tab (switching back
        /// restores it).
        static func resetDays(
            showingTodayOn tab: StatsTab,
            insulin: DailySelection,
            meals: DailySelection,
            nutrient: DailySelection
        ) {
            switch tab {
            case .insulin:
                insulin.select(nil)
            case .meals:
                meals.select(nil)
                nutrient.select(nil)
            case .agp,
                 .cgmOverview,
                 .cgmSensors,
                 .cgmSmoothing,
                 .daily,
                 .goodBadDays,
                 .hourOfDay,
                 .overview,
                 .patches,
                 .trace,
                 .weekday,
                 .weekly: break
            }
        }

        /// An item of the day selector, or the stepper's previous / next day.
        func select(traceDay day: TraceDay) {
            let shown = traceShownDay
            // a past day from its start; today (or after) as `.today`: it follows midnight
            if case let .day(date) = day {
                traceDay = TraceDay.of(date, today: Self.startOfToday, calendar: .current)
            } else {
                traceDay = day
            }
            if traceShownDay != shown {
                // the selector stays: its days don't depend on the day picked
                refresh(showLoading: true, reloadsTraceSelector: false)
            } else {
                // "Today" again after midnight: the new today
                refreshIfDayMovedOn()
            }
        }

        /// A day of Good & bad days' lists: the Day tab on that day (entering it selects today, `select(tab:)`, so the day
        /// is picked after). The way back is the title menu: Good & bad days' period and selection are kept.
        func openDay(_ day: Date) {
            if tab != .trace {
                tab = .trace
                resetSelections { selectEntering(.trace) }
            }
            traceDay = Self.openedDay(day, today: Self.startOfToday, calendar: .current)
            refresh(showLoading: true)
        }

        /// The Day tab's day for a day opened from a list: a past day from its start (today, or after it, as `.today`).
        /// - Parameter today: the start of today
        nonisolated static func openedDay(_ day: Date, today: Date, calendar: Calendar) -> TraceDay {
            TraceDay.of(day, today: today, calendar: calendar)
        }

        /// What the Day tab shows: the day picked, a past one kept inside the selector's days (midnight moves them on).
        var traceShownDay: TraceDay {
            traceDay.shown(today: Self.startOfToday, calendar: .current)
        }

        private static var startOfToday: Date {
            Calendar.current.startOfDay(for: Date())
        }

        /// the clock hour now, 0...23: what entering By hour, Insulin or Meals selects
        private static var currentClockHour: Int {
            GlucoseStatsEngine.clockHour(of: Date(), calendar: .current)
        }

        func select(period: StatsPeriod) {
            let shown = self.period
            // By weekday's or Good & bad days' own, or the other views' (`picking`)
            let picked = Self.picking(
                period,
                on: tab,
                preferred: preferredPeriod,
                weekday: weekdayPeriod,
                goodBadDays: goodBadDaysPeriod
            )
            if picked.preferred != preferredPeriod {
                preferredPeriod = picked.preferred
            }
            if picked.weekday != weekdayPeriod {
                weekdayPeriod = picked.weekday
            }
            if picked.goodBadDays != goodBadDaysPeriod {
                goodBadDaysPeriod = picked.goodBadDays
                // another period's stretches: its time opens on the new main stretch (not a pick: no hook)
                goodBadDaysSelection.showMainStretch()
            }
            if period != shown {
                refresh(showLoading: true)
            } else {
                refreshIfDayMovedOn()
            }
        }

        // MARK: - Midnight

        /// A pick on a chart, a stepper or a list (`onPick` of the selections): no request carries it.
        private func selectionPicked() {
            guard !resettingSelections else { return }
            refreshIfDayMovedOn()
        }

        /// The selections set by the screen itself (entering a tab, "Show Today"), not picked: the refresh that
        /// follows reads, none in place for them (`selectionPicked`).
        private func resetSelections(_ reset: () -> Void) {
            resettingSelections = true
            reset()
            resettingSelections = false
        }

        /// An interaction that reads nothing of its own (a pick, the same tab, period or day again, a page pushed or
        /// popped, the usual day): the first one after a midnight passed on screen reads again in place, so that today
        /// is today and the periods end at it. No observer, no timer: nothing reads while nobody looks.
        private func refreshIfDayMovedOn() {
            guard Self.dayMovedOn(since: lastRequestDay, today: Self.startOfToday) else { return }
            refresh(showLoading: false, reloadsTraceSelector: false)
        }

        /// The day of the last request isn't today (midnight, or a time zone change, passed since); false before the
        /// first request (`subscribe` makes it).
        /// - Parameters:
        ///   - requestDay: the start of the day of the last request
        ///   - today: the start of today
        nonisolated static func dayMovedOn(since requestDay: Date?, today: Date) -> Bool {
            guard let requestDay else { return false }
            return requestDay != today
        }

        /// The valid period nearest to `period` by |ln(days ratio)|, Today and 24 h counting as 1 day,
        /// 1 month as 35 and 3 months as 91; on a tie the first one offered; none offered (the Day tab): `period`.
        /// Nonisolated: the provider maps the Insulin and Meals tabs' periods with it too.
        nonisolated static func nearest(_ period: StatsPeriod, in periods: [StatsPeriod]) -> StatsPeriod {
            guard !periods.contains(period) else { return period }
            let target = log(Double(period.calendarDayCount ?? 1))
            func distance(_ candidate: StatsPeriod) -> Double {
                abs(log(Double(candidate.calendarDayCount ?? 1)) - target)
            }
            return periods.min { distance($0) < distance($1) } ?? period
        }

        // MARK: - Session

        /// A page of Statistics: the root, or one pushed over it (the Meals tab's Nutrients, and one nutrient's; a pod or
        /// patch of the Patches topic).
        enum Page: Hashable, Sendable {
            case root
            case nutrients
            case nutrient
            case patch
        }

        /// Statistics opened: the service keeps the readings the Day tab, AGP and By hour read until it closes. Every
        /// page calls it (and `disappear`); only the first one on screen counts, and not one that comes within a turn of
        /// the last one gone (a pop whose old page went first: nothing was torn down).
        func appear(_ page: Page = .root) {
            guard shownPages.appear(page) else {
                // a page pushed or popped while up
                refreshIfDayMovedOn()
                return
            }
            // before the refresh: its reads come with the readings held
            if sessionProvider == nil {
                let provider = self.provider
                sessionProvider = provider
                sessionTask = Task { [previous = self.sessionTask] in
                    await previous?.value
                    await provider.beginSession()
                }
            }
            // up again (the first time up, `subscribe` refreshes)
            if wentDown {
                wentDown = false
                invalidatePatches()
                refresh(showLoading: false)
                loadPatchTopicUnlessShown()
            } else {
                refreshIfDayMovedOn()
            }
        }

        /// The last page gone: one main-actor turn later, unless a page appeared meanwhile, the session closes (Close and
        /// the dismiss end it so; gone without a disappear, the deinit does).
        func disappear(_ page: Page = .root) {
            shownPages.disappear(page) { [weak self] in
                self?.tearDown()
            }
        }

        private func tearDown() {
            wentDown = true
            // an analysis in flight stops with the screen
            cgmSmoothing.cancel()
            guard let provider = sessionProvider else { return }
            sessionProvider = nil
            sessionTask = Task { [previous = self.sessionTask] in
                await previous?.value
                await provider.endSession()
            }
        }

        // MARK: - Computation

        /// the glucose views and Patches only: the Insulin and Meals tabs don't depend on them (`select(tab:)` refreshes on
        /// a switch)
        private func settingsChanged(_ settings: StatsSettings) {
            guard settings != self.settings else { return }
            // formatted in the old units: the Day tab's refresh loads it again (low/high and the HbA1c unit don't
            // change it)
            if settings.units != self.settings.units {
                clearUsualDay()
            }
            self.settings = settings
            patchesGeneration += 1
            // down: coming up reads (`wentDown`); not up yet, it is opening: read
            guard !wentDown, tab.usesSettings else { return }
            refresh(showLoading: true)
        }

        private var currentRequest: Request {
            Request(
                seq: refreshes.seq,
                tab: tab,
                period: period,
                settings: settings,
                traceDay: currentTraceDay
            )
        }

        private var currentTraceDay: TraceDay? {
            tab == .trace ? traceShownDay : nil
        }

        /// `isCurrent`. A result dropped only because the time moved what the screen shows (midnight moved the
        /// period's days under a picked day) has no newer refresh to replace it: refresh again.
        private func accepts(_ request: Request) -> Bool {
            guard isCurrent(request) else {
                if refreshes.isCurrent(request.seq) {
                    refresh(showLoading: false, reloadsTraceSelector: false)
                }
                return false
            }
            return true
        }

        /// still what the screen shows, and not replaced by a newer refresh; the Insulin and Meals tabs don't depend on the
        /// settings
        private func isCurrent(_ request: Request) -> Bool {
            guard refreshes.isCurrent(request.seq), request.tab == tab, request.period == period else { return false }
            guard request.tab.usesSettings else { return true }
            return request.settings == settings && request.traceDay == currentTraceDay
        }

        /// Recomputes what is shown. Cancels the computation in flight: a slow result (90 d) must never
        /// overwrite a newer one, and cancelling doesn't stop a call already running in the service, hence the
        /// request check after every await. `showLoading` dims the previous content (a new selection or settings);
        /// a refresh on coming back replaces it in place. On the Day tab it also reloads the selector
        /// (`loadTraceSelector`), except for a day picked (`reloadsTraceSelector` false), unless midnight passed since it
        /// was loaded.
        private func refresh(showLoading: Bool, reloadsTraceSelector: Bool = true) {
            // the one in flight cancelled; the request carries the new seq
            refreshes.begin()
            let request = currentRequest
            // the time of the request: the Day tab's today, the age for the reference intakes
            let requestedAt = Date()
            lastRequestDay = Calendar.current.startOfDay(for: requestedAt)

            if showLoading {
                switch request.tab {
                case .insulin:
                    insulinContent = .loading(previous: insulinContent.value)
                case .meals:
                    mealsContent = .loading(previous: mealsContent.value)
                case .patches:
                    patchesContent = .loading(previous: patchesContent.value)
                case .cgmOverview,
                     .cgmSensors,
                     .cgmSmoothing:
                    cgmContent = .loading(previous: cgmContent.value)
                case .agp,
                     .daily,
                     .goodBadDays,
                     .hourOfDay,
                     .overview,
                     .trace,
                     .weekday,
                     .weekly:
                    // the previous content only when it is of the same tab
                    let previous = glucoseContent.value.flatMap { $0.tab == request.tab ? $0 : nil }
                    glucoseContent = .loading(previous: previous)
                }
            }

            let factor = carbEquivalentFactor
            // Good & bad days' loop row: the slots by the setting's cadence
            let allowOneMinuteLoop = appCoordinator.settings.value.allowOneMinuteLoop
            // the age at the request: a birthday moves it at midnight, read by the next refresh
            let references = request.tab == .meals
                ? NutrientReferences(nutrientDemographics, now: requestedAt, calendar: .current)
                : nil
            // the patch in use's pump, and what the Patches topic's kept sessions are for
            let pumpInfo = appCoordinator.pumpInfo.value
            // the open session of the plugin delivering now is in use
            let deliveringPlugin = pumpInfo.flatMap { KnownPlugins.hasActiveDeliveryUnit($0) ? $0.identifier : nil }
            let patchesKey = request.tab == .patches ? patchesCacheKey(request) : nil
            let patchChanges = self.patchChanges
            // the CGM topic's content older than the newest minutes: read again (newer readings, a later now)
            if request.tab.isCGM, Self.cgmContentIsStale(asOf: cgmResult?.asOf, now: requestedAt) {
                self.cgmGeneration += 1
            }
            let cgmGeneration = self.cgmGeneration
            let cgmReadingsSeq = appCoordinator.glucoseStatsChanged.value.seq
            let provider = self.provider
            let task = Task { [weak self] in
                switch request.tab {
                case .overview:
                    let summary = await provider.summary(request.period, bands: request.settings.bands)
                    self?.show(request, in: \.glucoseContent) {
                        summary.isEmpty ? nil : .overview(Overview(summary, period: request.period, settings: request.settings))
                    }

                case .trace:
                    // today: the day of `requestedAt`
                    let range = (request.traceDay ?? .today).range(requestedAt: requestedAt, calendar: .current)
                    let trace = await provider.trace(range, bands: request.settings.bands)
                    // never empty: a day without readings shows "No readings" (the root shows "no data" from the
                    // selector, `TraceSelectorItem.nothingToShow`)
                    guard let self, self.show(request, in: \.glucoseContent, { .trace(Trace(trace, settings: request.settings)) })
                    else { return }
                    self.updateUsualDayOverlay()

                case .agp:
                    let agp = await provider.agp(request.period, bands: request.settings.bands)
                    self?.show(request, in: \.glucoseContent) {
                        agp.isEmpty ? nil : .agp(AGP(agp, period: request.period, settings: request.settings))
                    }

                case .goodBadDays:
                    let data = await provider.goodBadDays(
                        request.period,
                        bands: request.settings.bands,
                        allowOneMinuteLoop: allowOneMinuteLoop
                    )
                    self?.show(request, in: \.glucoseContent) {
                        data.isEmpty ? nil : .goodBadDays(GoodBadDays(data, settings: request.settings))
                    }

                case .daily:
                    let daily = await provider.daily(request.period, bands: request.settings.bands)
                    self?.show(request, in: \.glucoseContent) {
                        daily.isEmpty ? nil : .daily(Daily(daily, period: request.period, settings: request.settings))
                    }

                case .hourOfDay:
                    let hourOfDay = await provider.hourOfDay(request.period, bands: request.settings.bands)
                    self?.show(request, in: \.glucoseContent) {
                        hourOfDay.isEmpty
                            ? nil
                            : .hourOfDay(HourOfDay(hourOfDay, period: request.period, settings: request.settings))
                    }

                case .weekday:
                    let weekday = await provider.weekday(request.period, bands: request.settings.bands)
                    self?.show(request, in: \.glucoseContent) {
                        weekday.isEmpty ? nil : .weekday(Weekday(weekday, settings: request.settings))
                    }

                case .weekly:
                    let weekly = await provider.weekly(
                        request.period,
                        bands: request.settings.bands,
                        units: request.settings.units
                    )
                    self?.show(request, in: \.glucoseContent) {
                        weekly.isEmpty ? nil : .weekly(Weekly(weekly, period: request.period))
                    }

                case .insulin:
                    let insulin: InsulinResult
                    do {
                        insulin = try await provider.insulin(request.period)
                    } catch {
                        self?.readFailed(
                            request,
                            in: \.insulinContent,
                            shown: \.shown,
                            "Statistics: the insulin data couldn't be read",
                            error: error
                        )
                        return
                    }
                    self?.show(request, in: \.insulinContent) { insulin.isEmpty ? nil : Insulin(insulin) }

                case .meals:
                    let meals: MealsResult
                    do {
                        meals = try await provider.meals(request.period, factor: factor)
                    } catch {
                        self?.readFailed(
                            request,
                            in: \.mealsContent,
                            shown: \.shown,
                            "Statistics: the meals couldn't be read",
                            error: error
                        )
                        return
                    }
                    self?.show(request, in: \.mealsContent) { meals.isEmpty ? nil : Meals(meals, references: references) }

                case .patches:
                    let patches: PatchesResult
                    do {
                        guard let patchesKey else { return }
                        patches = try await provider.patches(
                            request.period,
                            key: patchesKey,
                            deliveringPlugin: deliveringPlugin,
                            changes: patchChanges,
                            currentPlugin: pumpInfo?.identifier
                        )
                    } catch is CancellationError {
                        // superseded by a newer read: nothing of this one is shown
                        return
                    } catch {
                        self?.readFailed(
                            request,
                            in: \.patchesContent,
                            shown: \.shown,
                            "Statistics: the patches couldn't be read",
                            error: error
                        )
                        return
                    }
                    // not on `show`: the topic is published before the content
                    guard let self, self.accepts(request) else { return }
                    self.update(patchTopic: patches.topic)
                    self.patchesContent = patches.isEmpty
                        ? .empty
                        : .loaded(Patches(patches, settings: request.settings))

                case .cgmOverview,
                     .cgmSensors,
                     .cgmSmoothing:
                    let cgm: CGMResult
                    do {
                        cgm = try await provider.cgm(request.period, generation: cgmGeneration)
                    } catch is CancellationError {
                        // superseded by a newer read: nothing of this one is shown
                        return
                    } catch {
                        self?.readFailed(
                            request,
                            in: \.cgmContent,
                            shown: \.period,
                            "Statistics: the CGM readings couldn't be read",
                            error: error
                        )
                        return
                    }
                    guard let self, self.accepts(request) else { return }
                    self.cgmResult = cgm
                    self.cgmReadingsSeq = cgmReadingsSeq
                    self.cgmContent = cgm.isEmpty ? .empty : .loaded(self.cgmReport(cgm, units: request.settings.units))
                }
            }
            refreshes.adopt(task)

            // after the trace's: it starts first
            if request.tab == .trace {
                // the baseline only when a change reached it (not every reading of today: 1/N of it, and an AGP of N
                // days each time), when midnight moved its window, or when it was never loaded (or dropped)
                let usualDayLoad: Task<Void, Never>? = usualDayShown && usualDayLoads.isDue(today: Self.startOfToday)
                    ? loadUsualDay()
                    : nil
                if reloadsTraceSelector || traceSelectorDay != Self.startOfToday {
                    // after the baseline when both load: its N days of readings stay held, so the selector's 90 days
                    // read from them (all of them for 90 d) instead of both reading them at once
                    loadTraceSelector(after: usualDayLoad)
                }
            }
        }

        /// The selector's 90 days, on their own task: a newer load replaces it (its result dropped), a day picked or a
        /// trace refresh doesn't cancel it. Dropped when the settings changed meanwhile (the in-range bars depend on the
        /// bands: the settings change loads it again).
        /// - Parameter previous: a load to wait for first (the usual day's, started in the same refresh)
        private func loadTraceSelector(after previous: Task<Void, Never>? = nil) {
            let settings = self.settings
            traceSelectorDay = Self.startOfToday
            let provider = self.provider
            traceSelectorLoads.start { [weak self] isCurrent in
                await previous?.value
                let items = await provider.traceSelector(bands: settings.bands)
                guard let self, isCurrent(), settings == self.settings else { return }
                // unchanged (a refresh of today with the same bar): kept, so the row isn't rebuilt
                if items != self.traceSelector {
                    self.traceSelector = items
                }
            }
        }

        /// A tab's result, when its request still is what the screen shows (`accepts`): nil is empty.
        /// - Returns: whether it was shown
        @discardableResult private func show<Value>(
            _ request: Request,
            in content: ReferenceWritableKeyPath<Stat.StateModel, ViewContent<Value>>,
            _ make: () -> Value?
        ) -> Bool {
            guard accepts(request) else { return false }
            self[keyPath: content] = make().map { .loaded($0) } ?? .empty
            return true
        }

        /// A tab's read that failed, when its request still is what the screen shows (`accepts`): logged, and the content
        /// on screen stays when it is this period's (`keepingPrevious`); a tab, a period or the foreground tries again.
        private func readFailed<Value>(
            _ request: Request,
            in content: ReferenceWritableKeyPath<Stat.StateModel, ViewContent<Value>>,
            shown: KeyPath<Value, StatsPeriod>,
            _ message: String,
            error: Error,
            file: String = #file,
            function: String = #function,
            line: UInt = #line
        ) {
            guard accepts(request) else { return }
            warning(.service, message, error: error, file: file, function: function, line: line)
            self[keyPath: content] = self[keyPath: content].keepingPrevious { $0[keyPath: shown] == request.period }
        }

        // MARK: - Patches

        private var patchTopicSeq = 0
        /// bumped by what makes the Patches topic's kept sessions stale that no change signal carries: coming back from
        /// the background (or up again), a settings change (`PatchesCacheKey.generation`). Not midnight: their numbers
        /// are by the activation, and each read picks its period anew
        private var patchesGeneration = 0

        /// Coming back from the background or up again: the kept sessions go, and the change log starts at the signals'
        /// values now (the foreground-only observers' redelivery after the rebuild is then no gap that drops them again).
        private func invalidatePatches() {
            patchesGeneration += 1
            patchChanges = PatchChangeLog(
                insulinSeq: appCoordinator.insulinStatsChanged.value.seq,
                glucoseSeq: appCoordinator.glucoseStatsChanged.value.seq
            )
        }

        /// the insulin and glucose statistics' changes noted while up: the Patches topic's kept sessions they touch go
        private var patchChanges = PatchChangeLog(insulinSeq: 0, glucoseSeq: 0)

        /// What all the Patches topic's kept sessions depend on, as of the request (`PatchesCacheKey`).
        private func patchesCacheKey(_ request: Request) -> PatchesCacheKey {
            PatchesCacheKey(
                bands: request.settings.bands,
                allowOneMinuteLoop: appCoordinator.settings.value.allowOneMinuteLoop,
                generation: patchesGeneration,
                timeZone: Calendar.current.timeZone.identifier
            )
        }

        /// The topic's naming, unless Patches is shown: its own read has it.
        private func loadPatchTopicUnlessShown() {
            guard tab != .patches else { return }
            loadPatchTopic()
        }

        /// The Patches topic's naming (the title menu offers the topic with it), on its own task: a newer load replaces
        /// it. A failed read keeps the one shown.
        private func loadPatchTopic() {
            patchTopicSeq += 1
            let seq = patchTopicSeq
            let plugin = appCoordinator.pumpInfo.value?.identifier
            let provider = self.provider
            Task { [weak self] in
                let topic: PatchTopic?
                do {
                    topic = try await provider.patchTopic(currentPlugin: plugin)
                } catch {
                    warning(.service, "Statistics: the patches couldn't be read", error: error)
                    return
                }
                guard let self, seq == self.patchTopicSeq else { return }
                self.update(patchTopic: topic)
            }
        }

        private func update(patchTopic topic: PatchTopic?) {
            if topic != patchTopic {
                patchTopic = topic
            }
        }

        // MARK: - CGM

        /// A CGM picked: formatted again from the result shown (a period without it shows the default); nothing is read.
        func select(cgm pick: CGMPick) {
            if pick != cgmPick {
                cgmPick = pick
                if let result = cgmResult, case .loaded = cgmContent {
                    cgmContent = .loaded(cgmReport(result, units: settings.units))
                }
            }
            refreshIfDayMovedOn()
        }

        /// The CGM topic's content for the pick, with the current smoothing setting, read only (the settings' mirror,
        /// `appCoordinator.settings`: `settingsManager.settings` is read asynchronously).
        private func cgmReport(_ result: CGMResult, units: GlucoseUnits) -> CGMReport {
            CGMReport(
                result,
                pick: cgmPick,
                units: units,
                smoothing: SmoothingCandidate(appCoordinator.settings.value.glucoseSmoothing),
                readingsSeq: cgmReadingsSeq,
                editor: cgmUnknownEditor
            )
        }

        /// The sheet reads the Unknown readings when it opens; a save or a clear reads the CGM topic again when it is
        /// shown (the sessions are in its cache key), the Unknown readings moved to their CGMs.
        private func connectCGMUnknownEditor() {
            let provider = self.provider
            cgmUnknownEditor.load = { try await provider.cgmUnknown() }
            cgmUnknownEditor.save = { [weak self] sessions, replacing in
                let saved = await provider.enterCGMSessions(sessions, replacing: replacing)
                self?.enteredCGMSessionsChanged()
                return saved
            }
            cgmUnknownEditor.clear = { [weak self] in
                let cleared = await provider.clearEnteredCGMSessions()
                self?.enteredCGMSessionsChanged()
                return cleared
            }
        }

        private func enteredCGMSessionsChanged() {
            guard tab.isCGM else { return }
            refresh(showLoading: true)
        }

        /// The newest minutes of readings, where a change (each new reading) doesn't make the CGM topic's content
        /// stale: a change from before them (a backfill, an edit) does, and so does content older than them.
        nonisolated static let cgmTrailingWindow: TimeInterval = .minutes(15)

        /// A readings change from before the newest minutes, or of all the readings (no interval).
        nonisolated static func cgmChangeInvalidates(_ change: StatsChange, now: Date) -> Bool {
            guard let interval = change.interval else { return true }
            return interval.start < now.addingTimeInterval(-cgmTrailingWindow)
        }

        /// Content read longer ago than the newest minutes; none read isn't stale.
        nonisolated static func cgmContentIsStale(asOf: Date?, now: Date) -> Bool {
            asOf.map { now.timeIntervalSince($0) > cgmTrailingWindow } ?? false
        }

        /// Analyse (or Analyse again): the smoothing replay of the content shown (its period and pick), off the main
        /// actor; as of the readings now.
        func analyseSmoothing() {
            guard let report = cgmContent.value else { return }
            let provider = self.provider
            let readingsSeq = appCoordinator.glucoseStatsChanged.value.seq
            cgmSmoothing.analyse(report.smoothing.key, readingsSeq: readingsSeq) { key, isCancelled, progress in
                try await provider.smoothingReplay(key.period, pick: key.pick, isCancelled: isCancelled, progress: progress)
            }
        }

        func cancelSmoothing() {
            cgmSmoothing.cancel()
        }

        // MARK: - Usual day

        /// The Day tab's toggle: shown, the baseline loads; hidden, it is dropped.
        func showUsualDay(_ shown: Bool) {
            if shown != usualDayShown {
                usualDayShown = shown
                displayPreferences.usualDayShown = shown
                if shown {
                    loadUsualDay()
                } else {
                    clearUsualDay()
                }
            }
            // after the baseline's load or drop: a refresh after midnight neither loads it again nor for nothing
            refreshIfDayMovedOn()
        }

        /// The usual day's baseline: the last 14, 30 or 90 days. The one shown stays until the new one is in (its key
        /// says which days it is).
        func select(usualDayPeriod period: StatsPeriod) {
            if period != usualDayPeriod, StatsPeriod.usualDayPeriods.contains(period) {
                usualDayPeriod = period
                displayPreferences.usualDayPeriod = period
                if usualDayShown {
                    loadUsualDay()
                }
            }
            // after the baseline's load, as `showUsualDay`
            refreshIfDayMovedOn()
        }

        /// The baseline, on its own task (the selector's rules): a newer load replaces it (its result dropped: every
        /// toggle, period pick and drop replaces or cancels it), a day picked or a trace refresh doesn't cancel it. Dropped
        /// when the units changed meanwhile (that change loads it again). One AGP of the last N days, the same for every
        /// day: stepping days doesn't recompute it. Its window moves on only at midnight (E clips no span), which the
        /// Day tab's next refresh catches (`UsualDayLoads.isDue`).
        @discardableResult private func loadUsualDay() -> Task<Void, Never> {
            let period = usualDayPeriod
            let settings = self.settings
            let provider = self.provider
            // published after the cache and the held readings took the change in, so the load reads it
            let changeSeq = appCoordinator.glucoseStatsChanged.value.seq
            return usualDayLoads.start(today: Self.startOfToday, changeSeq: changeSeq) { [weak self] isCurrent in
                let result = await provider.usualDay(period, bands: settings.bands)
                guard let self, isCurrent(), settings.units == self.settings.units else { return }
                let usual = UsualDay(result)
                if usual != self.usualDay {
                    self.usualDay = usual
                }
                self.updateUsualDayOverlay()
            }
        }

        private func clearUsualDay() {
            usualDayLoads.clear()
            usualDay = nil
            usualDayOverlay = nil
        }

        /// Places the baseline on the trace shown (or the one dimmed while the next comes in); nil when not shown, not
        /// loaded or not drawn (too few days). Published only when it changed.
        private func updateUsualDayOverlay() {
            var overlay: UsualDayOverlay?
            if usualDayShown, let usual = usualDay, usual.isDrawn, case let .trace(trace)? = glucoseContent.value {
                overlay = UsualDayOverlay(usual, plot: trace.plot)
            }
            if overlay != usualDayOverlay {
                usualDayOverlay = overlay
            }
        }
    }
}

/// The pages of a screen on screen, as their appear and disappear come: up with the first one in, down one main-actor
/// turn after the last one out, unless a page appears in that turn. A push or a pop may make the old page go before the
/// new one comes: the screen stays up across it instead of going down and up again.
@MainActor final class StatsPageSet<Page: Hashable> {
    private var shown = Set<Page>()
    private var pendingDown: Task<Void, Never>?
    /// between the first page in and the down
    private(set) var isUp = false

    /// nonisolated: a stored property's default value
    nonisolated init() {}

    /// - Returns: true when this page brought the screen up
    func appear(_ page: Page) -> Bool {
        shown.insert(page)
        pendingDown?.cancel()
        pendingDown = nil
        guard !isUp else { return false }
        isUp = true
        return true
    }

    /// The last page out: `down` one main-actor turn later, unless a page appears first.
    func disappear(_ page: Page, down: @escaping @MainActor @Sendable() -> Void) {
        guard shown.remove(page) != nil, shown.isEmpty, isUp, pendingDown == nil else { return }
        // a main-actor task: it runs after the job that made this call, and after the appear queued behind it
        pendingDown = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.pendingDown = nil
            guard self.shown.isEmpty else { return }
            self.isUp = false
            down()
        }
    }
}

/// "The latest task wins": a load started anew cancels the one in flight and drops its result. Cancelling doesn't stop
/// a call already running in a service, hence `isCurrent` after every await: a slow result (90 d) never shows over a
/// newer one.
@MainActor final class StatsLatestTask {
    /// the current load's, moved on by every `start`, `begin` and `cancel`
    private(set) var seq = 0
    private var task: Task<Void, Never>?

    /// nonisolated: a stored property's default value
    nonisolated init() {}

    /// Cancels the load in flight and drops its result: `seq` moves on, so a load holding the new seq (`begin`) is the
    /// current one, and none other.
    func cancel() {
        task?.cancel()
        task = nil
        seq += 1
    }

    /// A new load, before its task starts (a refresh: its request carries the seq; `adopt` its task next): the one in
    /// flight cancelled, its result dropped (`cancel`).
    /// - Returns: the new load's seq, the current one
    @discardableResult func begin() -> Int {
        cancel()
        return seq
    }

    /// From inside the load's task only (it reads `Task.isCancelled`): the task isn't cancelled, and `seq`, its own, still
    /// is the current one.
    func isCurrent(_ seq: Int) -> Bool {
        !Task.isCancelled && seq == self.seq
    }

    /// The current load's task, started by the caller after `begin`, so that the next `start`, `begin` or `cancel`
    /// cancels it.
    func adopt(_ task: Task<Void, Never>) {
        self.task = task
    }

    /// Cancels the load in flight and starts `body` as the current one; its `isCurrent` says, after each await, whether it
    /// still is.
    @discardableResult func start(
        _ body: @escaping @MainActor @Sendable(_ isCurrent: @escaping @MainActor @Sendable() -> Bool) async -> Void
    ) -> Task<Void, Never> {
        cancel()
        let seq = self.seq
        let task = Task { [weak self] in
            await body { self?.isCurrent(seq) ?? false }
        }
        self.task = task
        return task
    }
}

/// The Day tab's usual day loads (`Stat.StateModel.loadUsualDay`): the current one, the day it was asked for and the
/// readings changes it accounts for, so a Day tab refresh knows when to load it again. The baseline, its placement and
/// the two settings (shown, the period) stay on the model, published there.
@MainActor final class UsualDayLoads {
    /// every load and drop replaces the one in flight (its result dropped)
    private let loads = StatsLatestTask()
    /// the start of today when it was last asked for, nil when it never was (or was dropped): a Day tab refresh after
    /// midnight (coming back, a day picked) reloads it, its window moved on
    private var day: Date?
    /// the newest `glucoseStatsChanged` it accounts for: read by its load, or seen not to reach it
    private var seenSeq = 0
    /// a change since then reached it (`GlucoseStatsEngine.usualDayIsReached`): the next Day tab refresh reloads it
    private var stale = false

    /// nonisolated: a stored property's default value
    nonisolated init() {}

    /// Load it again: a change reached it, midnight moved its window, or it never was loaded (or was dropped).
    /// - Parameter today: the start of today
    func isDue(today: Date) -> Bool {
        stale || day != today
    }

    /// A load asked for today, as the current one (`StatsLatestTask.start`): it reads the changes up to `changeSeq`.
    /// - Parameters:
    ///   - today: the start of today
    ///   - changeSeq: the newest `glucoseStatsChanged`, published after the cache and the held readings took it in
    @discardableResult func start(
        today: Date,
        changeSeq: Int,
        _ body: @escaping @MainActor @Sendable(_ isCurrent: @escaping @MainActor @Sendable() -> Bool) async -> Void
    ) -> Task<Void, Never> {
        day = today
        seenSeq = Swift.max(seenSeq, changeSeq)
        stale = false
        return loads.start(body)
    }

    /// A readings change: does it reach the baseline (`GlucoseStatsEngine.usualDayIsReached`)? Then it is due.
    /// - Parameter today: the start of today
    func noteChange(_ change: StatsChange, today: Date) {
        guard change.seq > seenSeq else { return }
        if GlucoseStatsEngine.usualDayIsReached(by: change, seenSeq: seenSeq, today: today) {
            stale = true
        }
        seenSeq = change.seq
    }

    /// Dropped: the load in flight cancelled (its result dropped), and due when shown again.
    func clear() {
        loads.cancel()
        day = nil
    }
}
