import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var isRemoveCombinedTreatmentAlertPresented = false
        @State private var removeCombinedTreatmentAlert: Alert?
        @State private var isRemoveCarbsAlertPresented = false
        @State private var removeCarbsAlert: Alert?
        @State private var isRemoveInsulinAlertPresented = false
        @State private var removeInsulinAlert: Alert?
        @State private var isRemoveGlucoseAlertPresented = false
        @State private var isInsulinAmountAlertPresented = false
        @State private var removeGlucoseAlert: Alert?
        @State private var showManualGlucose: Bool = false
        @State private var showNonPumpInsulin: Bool = false

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

        private var fpuFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            VStack {
                Picker("Mode", selection: $state.mode) {
                    if state.isCombinedTreatments {
                        ForEach(Mode.allCases.indexed(), id: \.1) { index, item in
                            if item != .meals {
                                Text(item.name)
                                    .tag(index)
                            }
                        }
                    } else {
                        ForEach(Mode.allCases.indexed(), id: \.1) { index, item in
                            Text(item.name)
                                .tag(index)
                        }
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                historyContentView
            }
            .onAppear(perform: configureView)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                leading: Button("Close", action: state.hideModal),
                trailing: HStack {
                    if state.mode == .treatments && !showNonPumpInsulin {
                        Button(action: { showNonPumpInsulin = true }) {
                            Text(NSLocalizedString("Non-Pump Insulin", comment: "Non-Pump Insulin button text"))
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                    }
                    if state.mode == .glucose && !showManualGlucose {
                        Button(action: { showManualGlucose = true }) {
                            Text(NSLocalizedString("Glucose", comment: "Glucose button text"))
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            )
            .sheet(isPresented: $showManualGlucose) {
                addManualGlucoseView
            }
            .sheet(isPresented: $showNonPumpInsulin) {
                addNonPumpInsulinView
            }
        }

        var addManualGlucoseView: some View {
            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("New Glucose")
                                DecimalTextField(
                                    " ... ",
                                    value: $state.manualGlucose,
                                    formatter: glucoseFormatter,
                                    autofocus: true
                                )
                                Text(state.units.rawValue).foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            DatePicker("Date", selection: $state.manualGlucoseDate)
                        }

                        Section {
                            HStack {
                                let limitLow: Decimal = state.units == .mmolL ? 2.2 : 40
                                let limitHigh: Decimal = state.units == .mmolL ? 21 : 380

                                Button {
                                    state.addManualGlucose()
                                    showManualGlucose = false
                                }
                                label: { Text("Save") }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .disabled(state.manualGlucose < limitLow || state.manualGlucose > limitHigh)
                            }
                        }
                    }
                }
                .onAppear(perform: configureView)
                .navigationTitle("Add Glucose")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: { showManualGlucose = false
                    state.manualGlucose = 0 }))
            }
        }

        var addNonPumpInsulinView: some View {
            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text(NSLocalizedString("Amount", comment: ""))
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.nonPumpInsulinAmount,
                                    formatter: insulinFormatter,
                                    autofocus: true,
                                    cleanInput: true
                                )
                                Text("U").foregroundColor(.secondary)
                            }
                        }

                        Section {
                            DatePicker("Date", selection: $state.nonPumpInsulinDate)
                        }

                        let amountWarningCondition = (state.nonPumpInsulinAmount > state.maxBolus) &&
                            (state.nonPumpInsulinAmount <= state.maxBolus * 3)

                        Section {
                            HStack {
                                Button {
                                    state.addNonPumpInsulin()
                                    showNonPumpInsulin = false
                                }
                                label: {
                                    Text(NSLocalizedString("Log non-pump insulin", comment: "Log non-pump insulin button text"))
                                }
                                .foregroundColor(amountWarningCondition ? Color.white : Color.accentColor)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(
                                    state.nonPumpInsulinAmount <= 0 || state.nonPumpInsulinAmount > state
                                        .maxBolus * 3
                                )
                            }
                        }
                        header: {
                            if amountWarningCondition
                            {
                                Text(NSLocalizedString(
                                    "**⚠️ Warning!** The entered insulin amount is greater than your Max Bolus setting!",
                                    comment: "Non-pump insulin maxBolus * 3 alert text"
                                ))
                            }
                        }
                        .listRowBackground(
                            amountWarningCondition ? Color
                                .red : colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white
                        )
                    }
                }
                .onAppear(perform: configureView)
                .navigationTitle("Non-Pump Insulin")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: { showNonPumpInsulin = false
                    state.nonPumpInsulinAmount = 0 }))
            }
        }

        private var historyContentView: some View {
            Form {
                if state.isCombinedTreatments {
                    switch state.mode {
                    case .treatments: combinedTreatmentsList
                    case .meals: EmptyView()
                    case .glucose: glucoseList
                    }
                } else {
                    switch state.mode {
                    case .treatments: treatmentsList
                    case .meals: mealsList
                    case .glucose: glucoseList
                    }
                }
            }
        }

        private var combinedTreatmentsList: some View {
            List {
                ForEach(state.treatments) { treatment in
                    combinedTreatmentView(treatment)
                }
                .onDelete(perform: deleteTreatmentForCombined)
            }
            .alert(isPresented: $isRemoveCombinedTreatmentAlertPresented) {
                removeCombinedTreatmentAlert!
            }
        }

        private var treatmentsList: some View {
            List {
                if !state.treatments.isEmpty {
                    ForEach(state.treatments) { item in
                        treatmentView(item)
                    }
                    .onDelete(perform: deleteTreatment)
                } else {
                    HStack {
                        Text(NSLocalizedString("No data.", comment: "No data text when no entries in history list"))
                    }
                }
            }
            .alert(isPresented: $isRemoveInsulinAlertPresented) {
                removeInsulinAlert!
            }
        }

        private var mealsList: some View {
            List {
                if !state.meals.isEmpty {
                    ForEach(state.meals) { item in
                        mealView(item)
                    }
                    .onDelete(perform: deleteMeal)
                } else {
                    HStack {
                        Text(NSLocalizedString("No data.", comment: "No data text when no entries in history list"))
                    }
                }
            }
            .alert(isPresented: $isRemoveCarbsAlertPresented) {
                removeCarbsAlert!
            }
        }

        private var glucoseList: some View {
            List {
                if !state.glucose.isEmpty {
                    ForEach(state.glucose) { item in
                        glucoseView(item)
                    }
                    .onDelete(perform: deleteGlucose)
                } else {
                    HStack {
                        Text(NSLocalizedString("No data.", comment: "No data text when no entries in history list"))
                    }
                }
            }
            .alert(isPresented: $isRemoveGlucoseAlertPresented) {
                removeGlucoseAlert!
            }
        }

        @ViewBuilder private func combinedTreatmentView(_ treatment: Treatment) -> some View {
            HStack {
                Image(systemName: "circle.fill").foregroundColor(treatment.color)
                Text((treatment.isSMB ?? false) ? "SMB" : treatment.type.name)
                Text(treatment.amountText).foregroundColor(.secondary)

                if let duration = treatment.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                Spacer()

                Text(dateFormatter.string(from: treatment.date))
                    .moveDisabled(true)
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
                title: Text(NSLocalizedString("Delete Insulin?", comment: "Delete insulin from pump history and Nightscout")),
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
            var alertTitle = NSLocalizedString("Delete Carbs?", comment: "Delete carbs from data table and Nightscout")
            var alertMessage = meal.amountText

            if meal.type == .fpus {
                let fpus = state.meals
                let carbEquivalents = fpuFormatter.string(from: Double(
                    fpus.filter { fpu in
                        fpu.fpuID == meal.fpuID
                    }
                    .map { fpu in
                        fpu.amount ?? 0 }
                    .reduce(0, +)
                ) as NSNumber)!

                alertTitle = NSLocalizedString("Delete Carb Equivalents?", comment: "Delte fpus alert title")
                alertMessage = carbEquivalents + NSLocalizedString(" g", comment: "gram of carbs")
            }

            removeCarbsAlert = Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(
                    Text("Delete"),
                    action: { state.deleteCarbs(meal) }
                ),
                secondaryButton: .cancel()
            )

            isRemoveCarbsAlertPresented = true
        }

        private func deleteTreatmentForCombined(at offsets: IndexSet) {
            let treatment = state.treatments[offsets[offsets.startIndex]]
            var alertTitle = ""
            var alertMessage = ""

            if treatment.type == .carbs || treatment.type == .fpus {
                if treatment.type == .fpus {
                    let fpus = state.treatments
                    let carbEquivalents = fpuFormatter.string(from: Double(
                        fpus.filter { fpu in
                            fpu.fpuID == treatment.fpuID
                        }
                        .map { fpu in
                            fpu.amount ?? 0 }
                        .reduce(0, +)
                    ) as NSNumber)!

                    alertTitle = NSLocalizedString("Delete Carb Equivalents?", comment: "Delete fpus alert title")
                    alertMessage = carbEquivalents + NSLocalizedString(" g", comment: "gram of carbs")
                }

                if treatment.type == .carbs {
                    alertTitle = NSLocalizedString("Delete Carbs?", comment: "Delete carbs from data table and Nightscout")
                    alertMessage = treatment.amountText
                }

                removeCombinedTreatmentAlert = Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    primaryButton: .destructive(
                        Text("Delete"),
                        action: { state.deleteCarbs(treatment) }
                    ),
                    secondaryButton: .cancel()
                )
            } else {
                // treatment is .bolus

                alertTitle = NSLocalizedString("Delete Insulin?", comment: "Delete insulin from pump history and Nightscout")
                alertMessage = treatment.amountText

                removeCombinedTreatmentAlert = Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    primaryButton: .destructive(
                        Text("Delete"),
                        action: { state.deleteInsulin(treatment) }
                    ),
                    secondaryButton: .cancel()
                )
            }

            isRemoveCombinedTreatmentAlertPresented = true
        }

        private func deleteGlucose(at offsets: IndexSet) {
            let glucose = state.glucose[offsets[offsets.startIndex]]
            let glucoseValue = glucoseFormatter.string(from: Double(
                state.units == .mmolL ? Double(glucose.glucose.value.asMmolL) : glucose.glucose.value
            ) as NSNumber)! + " " + state.units.rawValue

            removeGlucoseAlert = Alert(
                title: Text(NSLocalizedString("Delete Glucose?", comment: "Delete Glucose alert title")),
                message: Text(glucoseValue),
                primaryButton: .destructive(
                    Text("Delete"),
                    action: { state.deleteGlucose(glucose) }
                ),
                secondaryButton: .cancel()
            )

            isRemoveGlucoseAlertPresented = true
        }
    }
}
