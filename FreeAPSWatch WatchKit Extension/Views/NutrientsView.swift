import SwiftUI

struct Constants {
    static let pickerHSpacing: CGFloat = 4
    static let defaultPickerStep = 5
}

struct NutrientsView: View {
    @EnvironmentObject var watchStateModel: WatchStateModel

    @State var carbsCount = 0
    @State var fatCount = 0
    @State var proteinCount = 0

    let defaultMaxCOB = 120
    var maxCOB: Int {
        if let unwrappedMaxCOB = watchStateModel.maxCOB {
            return Int(unwrappedMaxCOB)
        }
        return defaultMaxCOB
    }

    // Safety max Protein & max Fat cap set to double of maxCOB
    // For reference:
    // 500g of Chicken Breast contains around 155g of Protein
    // 500g of Bacon contains around 210g of Fat
    var defaultMaxProtein: Int { maxCOB * 2 }
    var defaultMaxFat: Int { maxCOB * 2 }

    var isSubmitButtonDisabled: Bool {
        carbsCount <= 0 && fatCount <= 0 && proteinCount <= 0
    }

    var body: some View {
        VStack {
            HStack(spacing: Constants.pickerHSpacing) {
                GramsPicker(
                    selection: $carbsCount,
                    label: NSLocalizedString("Carbs", comment: ""),
                    labelAlignment: .leading,
                    max: maxCOB,
                    accentColor: .white
                )

                GramsPicker(
                    selection: $proteinCount,
                    label: NSLocalizedString("Protein", comment: ""),
                    labelAlignment: .center,
                    max: defaultMaxProtein,
                    accentColor: .red
                )

                GramsPicker(
                    selection: $fatCount,
                    label: NSLocalizedString("Fat", comment: ""),
                    labelAlignment: .trailing,
                    max: defaultMaxFat,
                    accentColor: .orange
                )
            }
            .padding(.bottom, 24)
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    watchStateModel.isCarbsViewActive = false
                } label: {
                    Text("Cancel")
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Button {
                    WKInterfaceDevice.current().play(.click)
                    
                    watchStateModel.addNutrients([
                        .carbs: carbsCount,
                        .protein: proteinCount,
                        .fat: fatCount
                    ])
                } label: {
                    Text("Add")
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .opacity(isSubmitButtonDisabled ? 0.4 : 1)
                }
                .tint(.loopYellow)
                .disabled(isSubmitButtonDisabled)
            }
            .padding([.leading, .trailing], 4)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle("Nutrients")
        .onAppear {
            if let unwrappedCarbsRequired = watchStateModel.carbsRequired {
                carbsCount = Int(unwrappedCarbsRequired)
            }
        }
    }

    struct GramsPicker: View {
        @State var step = Constants.defaultPickerStep
        let labelFrameWidth = WKInterfaceDevice.current().screenBounds.width - 8

        @Binding var selection: Int
        let label: String
        let labelAlignment: Alignment
        let max: Int
        let accentColor: Color

        var body: some View {
            GeometryReader { geometry in
                Picker(selection: $selection) {
                    ForEach(0 ... (max / step), id: \.self) {
                        let value = $0 * step
                        Text("\(value) g")
                            .tag(value)
                            .foregroundColor(accentColor)
                            .font(.system(size: geometry.size.width / 2.5))
                            .minimumScaleFactor(0.01)
                            .lineLimit(1)
                    }
                } label: {
                    var labelFrameTranslationX: CGFloat {
                        let offset = geometry.size.width + Constants.pickerHSpacing
                        if labelAlignment == .leading { return offset }
                        if labelAlignment == .trailing { return -offset }
                        return 0
                    }
                    Text(label)
                        .font(.system(size: geometry.size.width / 3.5))
                        .bold()
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .foregroundColor(.black)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(accentColor)
                        )
                        .frame(width: labelFrameWidth, alignment: labelAlignment)
                        .transformEffect(.init(translationX: labelFrameTranslationX, y: 0))
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: geometry.size.width)
                .onTapGesture(count: 2, perform: handlePickerDoubleTapGesture)
            }
        }

        private func handlePickerDoubleTapGesture() {
            step = step == Constants.defaultPickerStep ? 1 : Constants.defaultPickerStep
            if step == Constants.defaultPickerStep {
                selection = Int(Double(selection / Constants.defaultPickerStep).rounded(.down)) * Constants
                    .defaultPickerStep
            }
        }
    }
}

struct NutrientsView_Previews: PreviewProvider {
    static var previews: some View {
        let watchStateModel = WatchStateModel()
        watchStateModel.carbsRequired = 110

        return Group {
            NutrientsView()
            NutrientsView()
                .previewDevice("Apple Watch Series 5 - 40mm")
            NutrientsView()
                .previewDevice("Apple Watch Series 3 - 38mm")
        }.environmentObject(watchStateModel)
    }
}
