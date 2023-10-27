import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var isRemoveTreatmentAlertPresented: Bool = false
        @State private var removeTreatmentAlert: Alert?
        @State private var isRemoveCarbsAlertPresented: Bool = false
        @State private var removeCarbsAlert: Alert?
        @State private var isRemoveInsulinAlertPresented: Bool = false
        @State private var removeInsulinAlert: Alert?
        @State private var showManualGlucose: Bool = false
        @State private var isAmountUnconfirmed: Bool = true

        @Environment(\.colorScheme) var colorScheme

        private var fpuFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.roundingMode = .ceiling
            }
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
                        Text(item.name).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                Form {
                    switch state.mode {
                    case .treatments: treatmentsList
                    case .glucose: glucoseList
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
            .sheet(isPresented: $showManualGlucose) {
                addGlucoseView
            }
        }

        private var treatmentsList: some View {
            List {
                ForEach(state.treatments) { item in
                    treatmentView(item)
                }
                .onDelete(perform: deleteTreatment)
            }
            .alert(isPresented: $isRemoveTreatmentAlertPresented) {
                removeTreatmentAlert!
            }
        }

        private var glucoseList: some View {
            List {
                HStack {
                    Text("Time").foregroundStyle(.secondary)
                    Spacer()
                    Text(state.units.rawValue).foregroundStyle(.secondary)
                    Button(
                        action: { showManualGlucose = true
                            state.manualGlucose = 0 },
                        label: { Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                        }
                    ).buttonStyle(.borderless)
                }
                if !state.glucose.isEmpty {
                    ForEach(state.glucose) { item in
                        glucoseView(item, isManual: item.glucose)
                    }
                    .onDelete(perform: deleteGlucose)
                } else {
                    HStack {
                        Text(NSLocalizedString("No data.", comment: "No data text when no entries in history list"))
                    }
                }
            }
        }

        var addGlucoseView: some View {
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
                                    autofocus: true,
                                    cleanInput: true
                                )
                                Text(state.units.rawValue).foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            HStack {
                                let limitLow: Decimal = state.units == .mmolL ? 0.8 : 40
                                let limitHigh: Decimal = state.units == .mgdL ? 14 : 720

                                Button {
                                    state.addManualGlucose()
                                    isAmountUnconfirmed = false
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
                .navigationBarItems(leading: Button("Close", action: { showManualGlucose = false }))
            }
        }

        @ViewBuilder private func treatmentView(_ item: Treatment) -> some View {
            HStack {
                Image(systemName: "circle.fill").foregroundColor(item.color)
                Text(dateFormatter.string(from: item.date))
                    .moveDisabled(true)
                Text((item.isSMB ?? false) ? "SMB" : item.type.name)
                Text(item.amountText).foregroundColor(.secondary)

                if let duration = item.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                if item.type == .carbs {
                    if item.note != "" {
                        Spacer()
                        Text(item.note ?? "").foregroundColor(.brown)
                    }
                }
            }
        }

        @ViewBuilder private func glucoseView(_ item: Glucose, isManual: BloodGlucose) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dateFormatter.string(from: item.glucose.dateString))
                    Spacer()
                    Text(item.glucose.glucose.map {
                        glucoseFormatter.string(from: Double(
                            state.units == .mmolL ? $0.asMmolL : Decimal($0)
                        ) as NSNumber)!
                    } ?? "--")
                    if isManual.type == GlucoseType.manual.rawValue {
                        Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                    } else {
                        Text(item.glucose.direction?.symbol ?? "--")
                    }
                }
            }
        }

        private func deleteTreatment(at offsets: IndexSet) {
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
                    alertTitle = NSLocalizedString(
                        "Delete Carbs?",
                        comment: "Delete carbs from data table and Nightscout"
                    )
                    alertMessage = treatment.amountText
                }

                removeTreatmentAlert = Alert(
                    title: Text(alertTitle),
                    message: Text("\n" + alertMessage),
                    primaryButton: .destructive(
                        Text("Delete"),
                        action: { state.deleteCarbs(treatment) }
                    ),
                    secondaryButton: .cancel()
                )
            } else {
                // treatment is .bolus
                alertTitle = NSLocalizedString(
                    "Delete Insulin?",
                    comment: "Delete insulin from pump history and Nightscout"
                )
                alertMessage = treatment.amountText

                removeTreatmentAlert = Alert(
                    title: Text(alertTitle),
                    message: Text("\n" + alertMessage),
                    primaryButton: .destructive(
                        Text("Delete"),
                        action: { state.deleteInsulin(treatment) }
                    ),
                    secondaryButton: .cancel()
                )
            }

            isRemoveTreatmentAlertPresented = true
        }

        private func deleteGlucose(at offsets: IndexSet) {
            state.deleteGlucose(at: offsets[offsets.startIndex])
        }
    }
}
