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
        VStack(spacing: 16) {
            HStack {
                Button {
                    let newValue = amount - 5
                    amount = max(newValue, 0)
                } label: { Image(systemName: "minus") }
                    .frame(width: 50)
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
                    let newValue = amount + 5
                    amount = min(newValue, Double(state.maxCOB ?? 120))
                } label: { Image(systemName: "plus") }
                    .frame(width: 50)
            }
            Button {
                state.addCarbs(10)
            }
            label: {
                HStack {
                    Image("carbs", bundle: nil)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.loopGreen)
                    Text("Add Carbs")
                }
            }
            .disabled(amount <= 0)
        }
        .navigationTitle("Add Carbs")
        .onAppear {
            amount = Double(state.carbsRequired ?? 0)
        }
    }
}

struct CarbsView_Previews: PreviewProvider {
    static var previews: some View {
        CarbsView().environmentObject(WatchStateModel())
    }
}
