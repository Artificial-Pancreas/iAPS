import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var isRemoveCarbsAlertPresented = false
        @State private var removeCarbsAlert: Alert?
        @State private var isRemoveInsulinAlertPresented = false
        @State private var removeInsulinAlert: Alert?
        @State private var newGlucose = false
        @State private var testAlert: Alert?
        @State private var isTestPresented = false

        @Environment(\.colorScheme) var colorScheme

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            VStack {
                Picker("Mode", selection: $state.mode) {
                    ForEach(Mode.allCases.indexed(), id: \.1) { index, item in
                        Text(item.name)
                            .tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .alert(isPresented: $isTestPresented) {
                    testAlert!
                }
                historyContent
            }
            .onAppear(perform: configureView)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                leading: Button("Close", action: state.hideModal),
                trailing: HStack {
                    if state.mode == .glucose && !newGlucose {
                        Button(action: { newGlucose = true }) {
                            Text("Add")
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        Spacer()
                    }
                }
            )
            .popup(isPresented: newGlucose, alignment: .top, direction: .bottom) {
                Form {
                    HStack {
                        Text("New Glucose")
                        DecimalTextField(" ... ", value: $state.manualGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue)
                    }.padding(.horizontal, 20)
                    HStack {
                        let limitLow: Decimal = state.units == .mmolL ? 2.2 : 40
                        let limitHigh: Decimal = state.units == .mmolL ? 21 : 380
                        Button { newGlucose = false }
                        label: { Text("Cancel") }.frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            state.addManualGlucose()
                            newGlucose = false
                        }
                        label: { Text("Save") }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .disabled(state.manualGlucose < limitLow || state.manualGlucose > limitHigh)

                    }.padding(20)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(colorScheme == .dark ? UIColor.systemGray2 : UIColor.systemGray6))
                )
            }
        }

        private var historyContent: some View {
            Form {
                switch state.mode {
                case .treatments: treatmentsList
                case .meals: mealsList
                case .glucose: glucoseList
                }
            }
        }

        private var treatmentsList: some View {
            List {
                ForEach(state.treatments) { item in
                    treatmentView(item)
                }

                .onDelete(perform: deleteTreatment)
            }
            .alert(isPresented: $isRemoveInsulinAlertPresented) {
                removeInsulinAlert!
            }
        }

        private var mealsList: some View {
            List {
                ForEach(state.meals) { item in
                    mealView(item)
                }
                .onDelete(perform: deleteMeal)
            }
            .alert(isPresented: $isRemoveCarbsAlertPresented) {
                removeCarbsAlert!
            }
        }

        private var glucoseList: some View {
            List {
                ForEach(state.glucose) { item in
                    glucoseView(item)
                }
                .onDelete(perform: deleteGlucose)
            }
        }

        @ViewBuilder private func treatmentView(_ bolus: Treatment) -> some View {
            HStack {
                Text((bolus.isSMB ?? false) ? "SMB" : bolus.type.name)
                Text(bolus.amountText).foregroundColor(.secondary)

                if let duration = bolus.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                Spacer()

                Text(dateFormatter.string(from: bolus.date))
                    .moveDisabled(true)
            }
        }

        @ViewBuilder private func mealView(_ meal: Treatment) -> some View {
            HStack {
                Text(meal.type.name)
                Text(meal.amountText).foregroundColor(.secondary)

                if let duration = meal.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                Spacer()

                Text(dateFormatter.string(from: meal.date))
                    .moveDisabled(true)
            }
        }

        @ViewBuilder private func glucoseView(_ item: Glucose) -> some View {
            HStack {
                Text(item.glucose.glucose.map {
                    glucoseFormatter.string(from: Double(
                        state.units == .mmolL ? $0.asMmolL : Decimal($0)
                    ) as NSNumber)!
                } ?? "--")
                Text(state.units.rawValue)
                Text(item.glucose.direction?.symbol ?? "--")

                Spacer()

                Text(dateFormatter.string(from: item.glucose.dateString))
            }
        }

        private func deleteTreatment(at offsets: IndexSet) {
            let treatment = state.treatments[offsets[offsets.startIndex]]

            removeInsulinAlert = Alert(
                title: Text("Delete insulin?"),
                message: Text(treatment.amountText),
                primaryButton: .destructive(
                    Text("Delete"),
                    action: { state.deleteInsulin(treatment) }
                ),
                secondaryButton: .cancel()
            )

            isRemoveInsulinAlertPresented = true
        }

        private func deleteMeal(at offsets: IndexSet) {
            let meal = state.meals[offsets[offsets.startIndex]]
            var alertTitle = Text("Delete carbs?")
            var alertMessage = Text(meal.amountText)

            if meal.type == .fpus {
                alertTitle = Text("Delete carb equivalents?")
                alertMessage = Text("")
            }

            removeCarbsAlert = Alert(
                title: alertTitle,
                message: alertMessage,
                primaryButton: .destructive(
                    Text("Delete"),
                    action: { state.deleteCarbs(meal) }
                ),
                secondaryButton: .cancel()
            )

            isRemoveCarbsAlertPresented = true
        }

        private func deleteGlucose(at offsets: IndexSet) {
            state.deleteGlucose(at: offsets[offsets.startIndex])
        }
    }
}
