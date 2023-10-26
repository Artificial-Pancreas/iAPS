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
        @State private var isAmountUnconfirmed: Bool = true
        @State private var showFutureEntries: Bool = true
        @State private var newGlucose = false
        @State private var isLayered = false
        @FocusState private var isFocused: Bool

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
            .navigationTitle(isLayered ? "" : "History")
            .blur(radius: isLayered ? 4.0 : 0)
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button(isLayered ? "" : "Close", action: state.hideModal))
            .popup(isPresented: newGlucose, alignment: .center, direction: .top) {
                addGlucose
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
                            Image(systemName: showFutureEntries ? "calendar.badge.minus" : "calendar.badge.plus")
                                .foregroundColor(Color.accentColor)
                            Text(showFutureEntries ? "Hide Future" : "Show Future")
                                .foregroundColor(Color.accentColor)
                                .font(.body)

                        }.frame(maxWidth: .infinity, alignment: .leading)

                    }).buttonStyle(.borderless)

                    Spacer()

                    Button(action: { showNonPumpInsulin = true
                        state.nonPumpInsulinDate = Date() }, label: {
                        HStack {
                            Text(
                                NSLocalizedString("External Insulin", comment: "External Insulin button text")
                            )
                            .foregroundColor(Color.accentColor)
                            .font(.body)

                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color.accentColor)
                        }.frame(maxWidth: .infinity, alignment: .trailing)

                    }).buttonStyle(.borderless)
                }

                if !state.treatments.isEmpty {
                    if showFutureEntries {
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
                Button {
                    newGlucose = true
                    isFocused = true
                    isLayered.toggle()
                }
                label: { Text("Add") }.frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)

                ForEach(state.glucose) { item in
                    glucoseView(item, isManual: item.glucose)
                }.onDelete(perform: deleteGlucose)
            }
        }

        private var addGlucose: some View {
            VStack {
                Form {
                    Section {
                        HStack {
                            Text("Glucose").font(.custom("popup", fixedSize: 18))
                            DecimalTextField(" ... ", value: $state.manualGlcuose, formatter: glucoseFormatter)
                                .focused($isFocused).font(.custom("glucose", fixedSize: 22))
                            Text(state.units.rawValue).foregroundStyle(.secondary)
                        }
                    }
                    header: {
                        Text("Blood Glucose Test").foregroundColor(.secondary).font(.custom("popupHeader", fixedSize: 12))
                            .padding(.top)
                    }
                    HStack {
                        Button {
                            newGlucose = false
                            isLayered = false
                        }
                        label: { Text("Cancel").foregroundColor(.red) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Button {
                            state.addManualGlucose()
                            newGlucose = false
                            isLayered = false
                        }
                        label: { Text("Save") }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .disabled(state.manualGlcuose <= 0)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .font(.custom("popupButtons", fixedSize: 16))
                }
            }
            .frame(minHeight: 220, maxHeight: 260).cornerRadius(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            ).shadow(radius: 40)
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
                    Text(state.units.rawValue)
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
