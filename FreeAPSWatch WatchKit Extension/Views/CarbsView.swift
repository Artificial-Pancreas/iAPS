import SwiftUI

struct CarbsView: View {
    @EnvironmentObject var state: WatchStateModel

    @State var amount = 0.0

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
        GeometryReader { geo in
            VStack(spacing: 16) {
                HStack {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        let newValue = amount - 5
                        amount = max(newValue, 0)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .frame(width: geo.size.width / 4)
                    Spacer()
                    Text(numberFormatter.string(from: amount as NSNumber)! + " g")
                        .font(.title2)
                        .focusable(true)
                        .digitalCrownRotation(
                            $amount,
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
                        let newValue = amount + 5
                        amount = min(newValue, Double(state.maxCOB ?? 120))
                    } label: { Image(systemName: "plus") }
                        .frame(width: geo.size.width / 4)
                }
                Button {
                    WKInterfaceDevice.current().play(.click)
                    // Get amount from displayed string
                    let amount = Int(numberFormatter.string(from: amount as NSNumber)!) ?? Int(amount.rounded())
                    state.addCarbs(amount)
                }
                label: {
                    HStack {
                        Image("carbs", bundle: nil)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.loopYellow)
                        Text("Add Carbs ")
                    }
                }
                .disabled(amount <= 0)
            }.frame(maxHeight: .infinity)
        }
        .navigationTitle("Add Carbs ")

        .onAppear {
            amount = Double(state.carbsRequired ?? 0)
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
