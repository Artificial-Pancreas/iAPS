import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        /// the Meals tab's Nutrients screen pushed (one nutrient's is pushed from it)
        @State private var nutrientsShown = false
        /// opened for the Nutrients screen (Home's meal card): pushed on the root's first appear, once (back from it
        /// isn't pushed again). Not as `nutrientsShown`'s initial value: a destination presented from the start of a
        /// stack in a fresh sheet isn't reliably pushed.
        @State private var pushesNutrients: Bool
        /// the card it was opened for (Home's On board card: the Negative IOB card), scrolled to once its content is
        /// first shown; dropped then, when the content comes in empty or failed, or at a view or a period picked first
        /// (a later chip tap never jumps)
        @State private var pendingFocus: StatsFocus?
        /// the Patches topic's session pushed (its detail), by its id (`PatchSession.id`): it follows the session
        /// across refreshes, and pops when one drops it
        @State private var patchDetailID = ""
        @State private var patchDetailShown = false

        /// - Parameters:
        ///   - nutrients: opened with the Meals tab's Nutrients screen pushed (Home's meal card); back goes to the Meals
        ///     tab
        ///   - focus: opened scrolled to that card (the Insulin tab's Negative IOB card)
        init(resolver: Resolver, period: StatsPeriod, tab: StatsTab, nutrients: Bool = false, focus: StatsFocus? = nil) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver, period: period, tab: tab))
            _pushesNutrients = State(initialValue: nutrients && tab == .meals)
            _pendingFocus = State(initialValue: tab == .insulin ? focus : nil)
        }

        var body: some View {
            VStack(spacing: 0) {
                controls
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .statsPageContent()
                    }
                    .onAppear { scroll(to: focusTarget, proxy) }
                    .onChange(of: focusTarget) { _, target in scroll(to: target, proxy) }
                }
            }
            // the title is the menu of the views: "Glucose · Overview", one line in the bar (inline, never large)
            .statsPage(title: StatsViewMenu.navigationTitle(state.tab, patches: state.patchTopic))
            .toolbarTitleMenu {
                StatsViewMenu(
                    selection: Binding(get: { state.tab }, set: { tab in
                        pendingFocus = nil
                        state.select(tab: tab)
                    }),
                    patches: state.patchTopic
                )
            }
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
            .onAppear {
                // the root first: the session is up before the push, and stays up as the root goes under the Nutrients
                // screen (`StatsPageSet`: either order within a turn)
                state.appear()
                guard pushesNutrients else { return }
                pushesNutrients = false
                nutrientsShown = true
            }
            .onDisappear { state.disappear() }
            .onChange(of: state.tab) { pendingFocus = nil }
            .onChange(of: state.period) { pendingFocus = nil }
            .onChange(of: insulinContentHasNoCards) { _, none in
                if none {
                    pendingFocus = nil
                }
            }
            .navigationDestination(isPresented: $patchDetailShown) {
                PatchDetailScreen(state: state, id: $patchDetailID, isShown: $patchDetailShown)
            }
            .navigationDestination(isPresented: $nutrientsShown) {
                NutrientsScreen(state: state)
            }
        }

        /// The view's period chips (the view is the title menu's); the Day tab has its day selector in their place,
        /// Weekly nothing (its 13 weeks only).
        private var controls: some View {
            VStack(spacing: 0) {
                if state.tab == .trace {
                    TraceDaySelector(
                        items: state.traceSelector,
                        selected: state.traceShownDay,
                        select: { state.select(traceDay: $0) }
                    )
                    .padding(.top, 4)
                } else if state.tab.hasPeriodControl {
                    PeriodPicker(
                        periods: state.validPeriods,
                        selection: Binding(get: { state.period }, set: { period in
                            pendingFocus = nil
                            state.select(period: period)
                        }),
                        // By weekday's whole weeks: "4 wk", "8 wk", "13 wk"
                        label: periodLabel(state.tab)
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                if state.tab.isCGM, let report = state.cgmContent.value, report.picker.isNotEmpty {
                    // the CGM topic's picker, under the chips: hidden with one CGM
                    CGMPickerControl(
                        items: report.picker,
                        selection: Binding(get: { report.pick }, set: { state.select(cgm: $0) })
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }

        /// The period chips' text: By weekday's by their weeks ("13 wk", not "3 mo").
        private func periodLabel(_ tab: StatsTab) -> (StatsPeriod) -> String {
            guard tab == .weekday else { return { StatsFormatting.label($0) } }
            return { StatsFormatting.weeksLabel($0) }
        }

        /// The card to scroll to, once the Insulin tab's content is there (its cards laid out).
        private var focusTarget: StatsFocus? {
            guard let pendingFocus, state.tab == .insulin, case .loaded = state.insulinContent else { return nil }
            return pendingFocus
        }

        /// The Insulin tab's content came in without its cards: no pump data, or the read failed.
        private var insulinContentHasNoCards: Bool {
            switch state.insulinContent {
            case .empty,
                 .failed: return true
            case .loaded,
                 .loading: return false
            }
        }

        /// One main-actor hop later, so the card's id is registered with the scroll view; not when the focus was
        /// dropped in between.
        private func scroll(to target: StatsFocus?, _ proxy: ScrollViewProxy) {
            guard let target else { return }
            Task { @MainActor in
                guard pendingFocus == target else { return }
                proxy.scrollTo(target, anchor: .top)
                pendingFocus = nil
            }
        }

        /// The Day tab's trace is never empty: it shows "no data" when none of the selector's days has a reading.
        private var glucoseContent: ViewContent<GlucoseContent> {
            state.tab == .trace && TraceSelectorItem.nothingToShow(state.traceSelector) ? .empty : state.glucoseContent
        }

        @ViewBuilder private var content: some View {
            if state.tab.isGlucose {
                glucoseTabContent
            } else if state.tab == .insulin {
                insulinTabContent
            } else if state.tab == .patches {
                patchesTabContent
            } else if state.tab.isCGM {
                cgmTabContent
            } else {
                mealsTabContent
            }
        }

        /// The CGM topic's three views, one result.
        @ViewBuilder private var cgmTabContent: some View {
            StatsContentView(
                content: state.cgmContent,
                emptyText: "No CGM data in this period",
                failedText: "The CGM readings couldn't be read."
            ) { report in
                if state.tab == .cgmSmoothing {
                    CGMSmoothingView(
                        report: report,
                        runs: state.cgmSmoothing,
                        analyse: { state.analyseSmoothing() },
                        cancel: { state.cancelSmoothing() }
                    )
                } else {
                    CGMView(report: report, tab: state.tab)
                }
            }
        }

        /// The glucose views, by the tab picked.
        @ViewBuilder private var glucoseTabContent: some View {
            let emptyText: LocalizedStringKey = switch state.tab {
            case .trace: "No CGM data in the last 90 days"
            // its weeks end yesterday: today's readings alone show nothing
            case .weekday: "No CGM data in these weeks: they end yesterday, today counts once it is over"
            // its days end yesterday, and a day needs 70% CGM coverage
            case .goodBadDays: "No day in this period has enough CGM data to be scored: the days end yesterday"
            default: "No CGM data in this period"
            }
            StatsContentView(content: glucoseContent, emptyText: emptyText) { glucose in
                switch glucose {
                case let .overview(overview):
                    OverviewView(overview: overview)
                case let .trace(trace):
                    TraceView(
                        trace: trace,
                        selector: state.traceSelector,
                        selectedDay: state.traceShownDay,
                        selectDay: { state.select(traceDay: $0) },
                        usualDayShown: Binding(get: { state.usualDayShown }, set: { state.showUsualDay($0) }),
                        usualDayPeriod: Binding(get: { state.usualDayPeriod }, set: { state.select(usualDayPeriod: $0) }),
                        usualDay: state.usualDay,
                        usualDayOverlay: state.usualDayOverlay
                    )
                case let .agp(agp):
                    AGPView(agp: agp, selection: state.agpSelection)
                case let .goodBadDays(goodBadDays):
                    GoodBadDaysView(
                        model: goodBadDays,
                        selection: state.goodBadDaysSelection,
                        openDay: { state.openDay($0) }
                    )
                case let .daily(daily):
                    DailyView(daily: daily, selection: state.dailySelection)
                case let .hourOfDay(hourOfDay):
                    HourOfDayView(hourOfDay: hourOfDay, selection: state.hourSelection)
                case let .weekday(weekday):
                    WeekdayView(weekday: weekday, selection: state.weekdaySelection)
                case let .weekly(weekly):
                    WeeklyView(weekly: weekly)
                }
            }
        }

        /// The Insulin tab.
        @ViewBuilder private var insulinTabContent: some View {
            StatsContentView(
                content: state.insulinContent,
                emptyText: "No pump data in this period",
                failedText: "The pump data couldn't be read."
            ) { insulin in
                InsulinView(
                    insulin: insulin,
                    daySelection: state.insulinDaySelection,
                    hourSelection: state.insulinHourSelection,
                    showToday: { state.showToday() }
                )
            }
        }

        /// The Patches tab, a row pushing its detail.
        @ViewBuilder private var patchesTabContent: some View {
            StatsContentView(
                content: state.patchesContent,
                emptyText: Self.patchesEmptyText(state.patchTopic),
                failedText: "The pump data couldn't be read."
            ) { patches in
                PatchesView(patches: patches, open: { id in
                    patchDetailID = id
                    patchDetailShown = true
                })
            }
        }

        /// The Meals tab, the way to the Nutrients screen.
        @ViewBuilder private var mealsTabContent: some View {
            StatsContentView(
                content: state.mealsContent,
                emptyText: "No carb entries in this period",
                failedText: "The carb entries couldn't be read."
            ) { meals in
                MealsView(
                    meals: meals,
                    daySelection: state.mealsDaySelection,
                    hourSelection: state.mealsHourSelection,
                    openNutrients: {
                        // the day it opens on first (yesterday), as entering the tab
                        state.nutrientDaySelection.select(nil)
                        nutrientsShown = true
                    },
                    showToday: { state.showToday() }
                )
            }
        }

        /// "No patches in this period", "No pods …", "No sites …"
        static func patchesEmptyText(_ topic: PatchTopic?) -> LocalizedStringKey {
            switch topic?.kind {
            case .pod: return "No pods in this period"
            case .site: return "No sites in this period"
            case nil,
                 .patch: return "No patches in this period"
            }
        }
    }
}
