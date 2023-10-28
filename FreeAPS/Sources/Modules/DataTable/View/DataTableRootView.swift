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
        @State private var showNonPumpInsulin: Bool = false
        @State private var showFutureEntries: Bool = false // default to hide future entries
        @State private var showManualGlucose: Bool = false
        @State private var isAmountUnconfirmed: Bool = true

        @Environment(\.colorScheme) var colorScheme

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
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
            .sheet(isPresented: $showNonPumpInsulin, onDismiss: { if isAmountUnconfirmed { state.nonPumpInsulinAmount = 0
                state.nonPumpInsulinDate = Date() } }) {
                addNonPumpInsulinView
            }
        }

        private var treatmentsList: some View {
            List {
                HStack {
                    Button(action: { showFutureEntries.toggle() }, label: {
                        HStack {
                            Image(systemName: "book.pages")
                                .foregroundColor(Color.accentColor)
                            Text(showFutureEntries ? "Hide Future" : "Show Future")
                                .foregroundColor(Color.secondary)
                                .font(.caption)

                        }.frame(maxWidth: .infinity, alignment: .leading)

                    }).buttonStyle(.borderless)

                    Spacer()

                    Button(action: { showNonPumpInsulin = true
                        state.nonPumpInsulinDate = Date() }, label: {
                        HStack {
                            Text("Add")
                                .foregroundColor(Color.secondary)
                                .font(.caption)

                            Image(systemName: "syringe")
                                .foregroundColor(Color.accentColor)
                        }.frame(maxWidth: .infinity, alignment: .trailing)

                    }).buttonStyle(.borderless)
                }

                if !state.treatments.isEmpty {
                    if !showFutureEntries {
                        ForEach(state.treatments.filter { item in
                            item.date <= Date()
                        }) { item in
                            treatmentView(item)
                        }
                    } else {
                        ForEach(state.treatments) { item in
                            treatmentView(item)
                        }
                    }
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
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeCarbsAlert = Alert(
                                title: Text("Delete carbs?"),
                                message: Text(item.amountText),
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: {
                                        state.deleteCarbs(item) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveCarbsAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveCarbsAlertPresented) {
                            removeCarbsAlert!
                        }
                }

                if item.type == .fpus {
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeCarbsAlert = Alert(
                                title: Text("Delete carb equivalents?"),
                                message: Text(""), // Temporary fix. New to fix real amount of carb equivalents later
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: { state.deleteCarbs(item) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveCarbsAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveCarbsAlertPresented) {
                            removeCarbsAlert!
                        }
                }

                if item.type == .bolus {
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeInsulinAlert = Alert(
                                title: Text("Delete insulin?"),
                                message: Text(item.amountText),
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: { state.deleteInsulin(item) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveInsulinAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveInsulinAlertPresented) {
                            removeInsulinAlert!
                        }
                }
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
                            DatePicker("Date", selection: $state.nonPumpInsulinDate, in: ...Date())
                        }

                        let amountWarningCondition = (state.nonPumpInsulinAmount > state.maxBolus) &&
                            (state.nonPumpInsulinAmount <= state.maxBolus * 3)

                        Section {
                            HStack {
                                Button {
                                    state.addNonPumpInsulin()
                                    isAmountUnconfirmed = false
                                    showNonPumpInsulin = false
                                }
                                label: {
                                    Text(NSLocalizedString(
                                        "Log non-pump insulin",
                                        comment: "Log non-pump insulin button text"
                                    ))
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
                                    "⚠️ Warning! The entered insulin amount is greater than your Max Bolus setting!",
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
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close", action: { showNonPumpInsulin = false
                    state.nonPumpInsulinAmount = 0 }))
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

        private func deleteGlucose(at offsets: IndexSet) {
            state.deleteGlucose(at: offsets[offsets.startIndex])
        }
    }
}
