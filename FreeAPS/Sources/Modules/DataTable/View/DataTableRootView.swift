import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @Environment(\.colorScheme) var colorScheme

        @State private var isRemoveHistoryItemAlertPresented: Bool = false
        @State private var alertTitle: String = ""
        @State private var alertMessage: String = ""

        @State private var alertTreatmentToDelete: Treatment?
        @State private var alertGlucoseToDelete: Glucose?

        @State private var showExternalInsulin: Bool = false
        @State private var showFutureEntries: Bool = false // default to hide equivalents
        @State private var showManualGlucose: Bool = false
        @State private var editIsPresented: Bool = false
        @State private var isAmountUnconfirmed: Bool = true

        @FetchRequest(
            entity: Carbohydrates.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "date > %@", DateFilter().day)
        ) private var meals: FetchedResults<Carbohydrates>

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal

            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.roundingMode = .halfUp
            } else {
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        private var manualGlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.roundingMode = .ceiling
            } else {
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }

        private var hourFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
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
                    case .treatments:
                        treatmentsList
                    case .glucose: glucoseList
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
            .onAppear(perform: configureView)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
            .sheet(isPresented: $showManualGlucose) {
                addGlucoseView
            }
            .sheet(isPresented: $showExternalInsulin, onDismiss: { if isAmountUnconfirmed { state.externalInsulinAmount = 0
                state.externalInsulinDate = Date() } }) {
                addExternalInsulinView
            }
            .sheet(isPresented: $editIsPresented) { edit }
        }

        private var treatmentsList: some View {
            List {
                HStack {
                    Button(action: { showExternalInsulin = true
                        state.externalInsulinDate = Date() }, label: {
                        HStack {
                            Image(systemName: "syringe")
                            Text("Add Insulin")
                                .foregroundColor(Color.secondary)
                                .font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }).buttonStyle(.borderless)
                    Spacer()
                }

                HStack {
                    HStack {
                        Text("Total")
                        Text(insulinFormatter.string(from: (state.tdd.0 + state.tdd.1) as NSNumber) ?? "")
                        Text("U")
                    }
                    Spacer()
                    HStack {
                        Text(hourFormatter.string(from: state.tdd.2 as NSNumber) ?? "")
                        Text("h")
                    }
                }.foregroundStyle(.gray)

                HStack {
                    HStack {
                        Text("Today")
                        Text(insulinFormatter.string(from: (state.insulinToday.0 + state.insulinToday.1) as NSNumber) ?? "")
                        Text("U")
                    }
                    Spacer()
                    HStack {
                        Text(hourFormatter.string(from: state.insulinToday.2 as NSNumber) ?? "")
                        Text("h")
                    }
                }.foregroundStyle(.gray)

                if !state.treatments.isEmpty {
                    ForEach(state.treatments) { item in
                        treatmentView(item)
                    }
                } else {
                    HStack {
                        Text("No data.")
                    }
                }
            }
        }

        private var glucoseList: some View {
            List {
                HStack {
                    Button(
                        action: { showManualGlucose = true
                            state.manualGlucose = 0 },
                        label: { Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                        }
                    ).buttonStyle(.borderless)
                    Text(state.units.rawValue).foregroundStyle(.secondary)
                    Spacer()
                    Text("Time").foregroundStyle(.secondary)
                }
                if !state.glucose.isEmpty {
                    ForEach(state.glucose) { item in
                        glucoseView(item, isManual: item.glucose)
                    }
                } else {
                    HStack {
                        Text("No data.")
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
                                    formatter: manualGlucoseFormatter,
                                    autofocus: true,
                                    liveEditing: true
                                )
                                Text(state.units.rawValue).foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            HStack {
                                let limitLow: Decimal = state.units == .mmolL ? 0.8 : 14
                                let limitHigh: Decimal = state.units == .mmolL ? 40 : 720
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
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("Close", action: { showManualGlucose = false }))
            }
        }

        @ViewBuilder private func treatmentView(_ item: Treatment) -> some View {
            VStack {
                if item.type == .carbs, let meal = filtered(date: item.creationDate) {
                    HStack {
                        Image(systemName: "fork.knife.circle.fill").foregroundStyle(Color.loopYellow)
                        Text("Meal")
                        Spacer()
                        Text(dateFormatter.string(from: item.date))
                            .moveDisabled(true)
                    }.padding(.bottom, 1)

                    // Horizontal adjustments
                    let leading: CGFloat = 28
                    let trailing: CGFloat = -100
                    let height: CGFloat = 15

                    if meal.carbs != 0 {
                        HStack(spacing: 0) {
                            Text("Carbs").frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.amountText).frame(maxWidth: .infinity, alignment: .trailing).offset(x: trailing)
                        }
                        .frame(maxHeight: height)
                        .padding(.leading, leading)
                        .foregroundStyle(.secondary)
                    }

                    if meal.fat != 0 {
                        HStack(spacing: 0) {
                            Text("Fat").frame(maxWidth: .infinity, alignment: .leading)
                            Text(
                                (hourFormatter.string(from: (meal.fat ?? 0) as NSNumber) ?? "") +
                                    NSLocalizedString(" g", comment: "")
                            ).frame(maxWidth: .infinity, alignment: .trailing).offset(x: trailing)
                        }
                        .frame(maxHeight: height)
                        .padding(.leading, leading)
                        .foregroundStyle(.secondary)
                    }

                    if meal.protein != 0 {
                        HStack(spacing: 0) {
                            Text("Protein").frame(maxWidth: .infinity, alignment: .leading)
                            Text(
                                (hourFormatter.string(from: (meal.protein ?? 0) as NSNumber) ?? "") +
                                    NSLocalizedString(" g", comment: "")
                            ).frame(maxWidth: .infinity, alignment: .trailing).offset(x: trailing)
                        }
                        .frame(maxHeight: height)
                        .padding(.leading, leading)
                        .foregroundStyle(.secondary)
                    }

                } else if item.type == .carbs {
                    HStack {
                        Image(systemName: "circle.fill").foregroundStyle(item.color)

                        Text(item.type.name)
                        Text(item.amountText).foregroundColor(.secondary)
                        Spacer()
                        Text(dateFormatter.string(from: item.date))
                            .moveDisabled(true)
                    }
                } else {
                    HStack {
                        if item.type == .bolus {
                            Image(systemName: "circle.fill").foregroundStyle(item.color)
                        } else {
                            Image(systemName: "circle.fill").foregroundStyle(item.color)
                        }
                        Text((item.isSMB ?? false) ? "SMB" : item.type.name)
                        Text(item.amountText).foregroundColor(.secondary)

                        if let duration = item.durationText {
                            Text(duration).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dateFormatter.string(from: item.date))
                            .moveDisabled(true)
                    }
                }
            }.padding(.vertical, (item.type == .carbs || item.type == .bolus) ? 10 : 0)
                .swipeActions(edge: .leading) {
                    Button {
                        state.updateVariables(mealItem: item, complex: filtered(date: item.creationDate))
                        editIsPresented.toggle()
                    }
                    label: { Label("Edit", systemImage: "pencil.line") }
                }.disabled(item.type != .carbs)
                .swipeActions {
                    Button(
                        "Delete",
                        systemImage: "trash.fill",
                        role: .none,
                        action: {
                            alertTreatmentToDelete = item

                            if item.type == .carbs {
                                alertTitle = "Delete Carbs?"
                                alertMessage = dateFormatter.string(from: item.date) + ", " + item.amountText
                            } else {
                                // item is insulin treatment; item.type == .bolus
                                alertTitle = "Delete Insulin?"
                                alertMessage = dateFormatter.string(from: item.date) + ", " + item.amountText

                                if item.isSMB ?? false {
                                    // Add text snippet, so that alert message is more descriptive for SMBs
                                    alertMessage += "SMB"
                                }
                            }

                            isRemoveHistoryItemAlertPresented = true
                        }
                    ).tint(.red)
                }.disabled(item.type == .tempBasal || item.type == .tempTarget || item.type == .resume || item.type == .suspend)
                .alert(
                    Text(NSLocalizedString(alertTitle, comment: "")),
                    isPresented: $isRemoveHistoryItemAlertPresented
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        guard let treatmentToDelete = alertTreatmentToDelete else {
                            debug(.default, "Cannot unwrap alertTreatmentToDelete!")
                            return
                        }

                        if treatmentToDelete.type == .carbs {
                            state.deleteCarbs(treatmentToDelete.creationDate)
                        } else {
                            state.deleteInsulin(treatmentToDelete)
                        }
                    }
                } message: {
                    Text("\n" + NSLocalizedString(alertMessage, comment: ""))
                }
        }

        var addExternalInsulinView: some View {
            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("Amount")
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.externalInsulinAmount,
                                    formatter: insulinFormatter,
                                    autofocus: true,
                                    liveEditing: true
                                )
                                Text("U").foregroundColor(.secondary)
                            }
                        }

                        Section {
                            DatePicker("Date", selection: $state.externalInsulinDate, in: ...Date())
                        }

                        let amountWarningCondition = (state.externalInsulinAmount > state.maxBolus)

                        Section {
                            HStack {
                                Button {
                                    state.addExternalInsulin()
                                    isAmountUnconfirmed = false
                                    showExternalInsulin = false
                                }
                                label: {
                                    Text("Log external insulin")
                                }
                                .foregroundColor(amountWarningCondition ? Color.white : Color.accentColor)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(
                                    state.externalInsulinAmount <= 0 || state.externalInsulinAmount > state.maxBolus * 3
                                )
                            }
                        }
                        header: {
                            if amountWarningCondition
                            {
                                Text("⚠️ Warning! The entered insulin amount is greater than your Max Bolus setting!")
                            }
                        }
                        .listRowBackground(
                            amountWarningCondition ? Color
                                .red : colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white
                        )
                    }
                }
                .onAppear(perform: configureView)
                .navigationTitle("External Insulin")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("Close", action: { showExternalInsulin = false
                    state.externalInsulinAmount = 0 }))
            }
        }

        @ViewBuilder private func glucoseView(_ item: Glucose, isManual: BloodGlucose) -> some View {
            HStack {
                Text(item.glucose.glucose.map {
                    (
                        isManual.type == GlucoseType.manual.rawValue ?
                            manualGlucoseFormatter :
                            glucoseFormatter
                    )
                    .string(from: Double(
                        state.units == .mmolL ? $0.asMmolL : Decimal($0)
                    ) as NSNumber)!
                } ?? "--")
                if isManual.type == GlucoseType.manual.rawValue {
                    Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                } else {
                    Text(item.glucose.direction?.symbol ?? "--")
                }
                Spacer()

                Text(dateFormatter.string(from: item.glucose.dateString))
            }
            .swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: {
                        alertGlucoseToDelete = item
                        let valueText = (
                            isManual.type == GlucoseType.manual.rawValue ?
                                manualGlucoseFormatter :
                                glucoseFormatter
                        ).string(from: Double(
                            state.units == .mmolL ? Double(item.glucose.value.asMmolL) : item.glucose.value
                        ) as NSNumber)! + " " + state.units.rawValue
                        alertTitle = "Delete Glucose?"
                        alertMessage = dateFormatter.string(from: item.glucose.dateString) + ", " + valueText
                        isRemoveHistoryItemAlertPresented = true
                    }
                ).tint(.red)
            }
            .alert(
                Text(NSLocalizedString(alertTitle, comment: "")),
                isPresented: $isRemoveHistoryItemAlertPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard let glucoseToDelete = alertGlucoseToDelete else {
                        print("Cannot unwrap alertTreatmentToDelete!")
                        return
                    }
                    state.deleteGlucose(glucoseToDelete)
                }
            } message: {
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }

        private var edit: some View {
            VStack(spacing: 0) {
                if let item = state.treatment {
                    Button { editIsPresented = false }
                    label: { Text("Cancel") }.frame(maxWidth: .infinity, alignment: .trailing)
                        .tint(.blue).buttonStyle(.borderless).padding(.top, 20).padding(.trailing, 20)
                    Form {
                        // Edit a meal
                        Section {
                            HStack {
                                Text("Carbs")
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.meal.carbs,
                                    formatter: hourFormatter,
                                    autofocus: true,
                                    liveEditing: true
                                )
                                Text("grams").foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Fat").foregroundColor(.orange)
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.meal.fat,
                                    formatter: hourFormatter,
                                    autofocus: false,
                                    liveEditing: true
                                )
                                Text("grams").foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Protein").foregroundColor(.red)
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.meal.protein,
                                    formatter: hourFormatter,
                                    autofocus: false,
                                    liveEditing: true
                                ).foregroundColor(.loopRed)

                                Text("grams").foregroundColor(.secondary)
                            }
                        } header: { Text("Meal") }

                        Section {
                            Button {
                                editIsPresented.toggle()
                                state.updateCarbs(treatment: item, computed: filtered(date: item.creationDate))
                            }
                            label: { Text("Save") }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .listRowBackground(Color(.systemBlue))
                                .tint(.white)
                        }
                    }
                }
            }
        }

        private func filtered(date: Date) -> Carbohydrates? {
            meals
                .first(where: {
                    ($0.date ?? .distantPast).timeIntervalSince(date) > -1.0 && ($0.date ?? .distantPast)
                        .timeIntervalSince(date) < 1
                })
        }
    }
}
