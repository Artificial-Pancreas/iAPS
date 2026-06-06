import Charts
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        enum Duration: String, CaseIterable, Identifiable {
            case Today
            case Day
            case Week
            case Month
            case Total
            var id: Self { self }
        }

        @State private var selectedDuration: Duration = .Today

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        @ViewBuilder func stats() -> some View {
            ZStack {
                Color.gray.opacity(0.05).ignoresSafeArea(.all)
                let filter = DateFilter.self
                switch selectedDuration {
                case .Today:
                    StatsView(
                        filter: filter.today.startDate,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Day:
                    StatsView(
                        filter: filter.day.startDate,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Week:
                    StatsView(
                        filter: filter.week.startDate,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Month:
                    StatsView(
                        filter: filter.month.startDate,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Total:
                    StatsView(
                        filter: filter.total.startDate,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                }
            }
        }

        @ViewBuilder func chart() -> some View {
            let filter = DateFilter.self
            switch selectedDuration {
            case .Today:
                ChartsView(
                    filter: filter.today.startDate,
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart
                )
            case .Day:
                ChartsView(
                    filter: filter.day.startDate,
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart
                )
            case .Week:
                ChartsView(
                    filter: filter.week.startDate,
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart
                )
            case .Month:
                ChartsView(
                    filter: filter.month.startDate,
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart
                )
            case .Total:
                ChartsView(
                    filter: filter.total.startDate,
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart
                )
            }
        }

        var body: some View {
            VStack(alignment: .center) {
                chart().padding(.top, 20)
                Picker("Duration", selection: $selectedDuration) {
                    ForEach(Duration.allCases) { duration in
                        Text(NSLocalizedString(duration.rawValue, comment: "")).tag(duration)
                    }
                }
                .pickerStyle(.segmented).background(.cyan.opacity(0.2))
                stats()
            }
            .background(Color(.systemBackground)) // New iOS 26 bug
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .navigationBarTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }
    }
}
