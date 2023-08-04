import SwiftUI

struct CarbsView: View {
    @EnvironmentObject var state: WatchStateModel

    @State var carbAmount = 0.0
    @State var fatAmount = 0.0
    @State var proteinAmount = 0.0
    @State var selectCarbs: Bool = false
    @State var selectFat: Bool = false
    @State var selectProtein: Bool = false
    @State var colorOfselection: Color = .darkGray

    var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = (state.maxCOB ?? 120) as NSNumber
        formatter.maximumFractionDigits = 0
        formatter.allowsFloats = false
        return formatter
    }

    var body: some View {
        VStack(spacing: 5) {
            // Carbs
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = carbAmount - 5
                    carbAmount = max(newValue, 0)
                } label: {
                    Image(systemName: "minus.circle")
                }.buttonStyle(.borderless)
                Spacer()
                Text("🥨")
                Spacer()
                Text(numberFormatter.string(from: carbAmount as NSNumber)! + " g")
                    .font(.title2)
                    .focusable(true)
                    .digitalCrownRotation(
                        $carbAmount,
                        from: 0,
                        through: Double(state.maxCOB ?? 120),
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                Spacer()
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = carbAmount + 5
                    carbAmount = min(newValue, Double(state.maxCOB ?? 120))
                } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
            }
            .onTapGesture {
                selectCarbs = true
                selectProtein = false
                selectFat = false
            }
            .background(selectCarbs && state.displayFatAndProteinOnWatch ? colorOfselection : .black)
            .padding(.top)

            if state.displayFatAndProteinOnWatch {
                // Protein
                HStack {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        let newValue = proteinAmount - 5
                        proteinAmount = max(newValue, 0)
                    } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless)
                    // .frame(width: geo.size.width / 6)
                    Spacer()
                    Text("🍗")
                    Spacer()
                    Text(numberFormatter.string(from: proteinAmount as NSNumber)! + " g")
                        .font(.title2).foregroundStyle(.red)
                        .focusable(true)
                        .digitalCrownRotation(
                            $proteinAmount,
                            from: 0,
                            through: Double(240),
                            by: 1,
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                    Spacer()
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        let newValue = proteinAmount + 5
                        proteinAmount = min(newValue, Double(240))
                    } label: { Image(systemName: "plus.circle") }
                        .buttonStyle(.borderless)
                }
                .onTapGesture {
                    selectProtein = true
                    selectCarbs = false
                    selectFat = false
                }
                .background(selectProtein ? colorOfselection : .black)

                // Fat
                HStack {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        let newValue = fatAmount - 5
                        fatAmount = max(newValue, 0)
                    } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless)
                    Spacer()
                    Text("🧀")
                    Spacer()
                    Text(numberFormatter.string(from: fatAmount as NSNumber)! + " g")
                        .font(.title2).foregroundStyle(Color(.loopYellow))
                        .focusable(true)
                        .digitalCrownRotation(
                            $fatAmount,
                            from: 0,
                            through: Double(240),
                            by: 1,
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                    Spacer()
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        let newValue = fatAmount + 5
                        fatAmount = min(newValue, Double(240))
                    } label: { Image(systemName: "plus.circle") }
                        .buttonStyle(.borderless)
                }
                .onTapGesture {
                    selectProtein = false
                    selectCarbs = false
                    selectFat = true
                }
                .background(selectFat ? colorOfselection : .black)
            }

            Button {
                WKInterfaceDevice.current().play(.click)
                // Get amount from displayed string
                let amountCarbs = Int(numberFormatter.string(from: carbAmount as NSNumber)!) ?? Int(carbAmount.rounded())
                let amountFat = Int(numberFormatter.string(from: fatAmount as NSNumber)!) ?? Int(fatAmount.rounded())
                let amountProtein = Int(numberFormatter.string(from: proteinAmount as NSNumber)!) ??
                    Int(proteinAmount.rounded())
                state.addMeal(amountCarbs, fat: amountFat, protein: amountProtein)
            }
            label: {
                HStack {
                    Text("Add")
                }
            }
            .disabled(carbAmount <= 0 && fatAmount <= 0 && proteinAmount <= 0)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .buttonStyle(.borderless)
            .padding(.top)
        }
        .onAppear {
            carbAmount = Double(state.carbsRequired ?? 0)
        }
    }
}

struct CarbsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = WatchStateModel()
        state.carbsRequired = 120
        return Group {
            CarbsView()
            CarbsView().previewDevice("Apple Watch Series 5 - 40mm")
            CarbsView().previewDevice("Apple Watch Series 3 - 38mm")
        }
        .environmentObject(state)
    }
}
