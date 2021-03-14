import SwiftUI

struct GlucoseInformationBarView: View {
    let data: [InformationBarEntryData]
    let glucoseValue: Double
    let glucoseDelta: Double
    let direction: BloodGlucose.Direction

    var body: some View {
        let halvedEntryData = data.halve()
        HStack {
            VStack {
                ForEach(halvedEntryData, id: \.self) { half in
                    HStack {
                        ForEach(half, id: \.self) { dataEntry in
                            Text(
                                dataEntry.label + "\n" +
                                    APSDataFormatter.format(
                                        inputValue: dataEntry.value,
                                        to: dataEntry.type
                                    )
                            )
                            .font(.footnote)
                            .informationBarEntryStyle()
                            .padding(.bottom, 1)
                        }
                    }
                }
            }
            Text(APSDataFormatter.format(inputValue: glucoseValue, to: .glucose))
                .font(.largeTitle)
                .foregroundColor(Color(.systemBlue))
                .informationBarEntryStyle()
            VStack {
                GlucoseArrowView(direction: direction)
                    .padding(.bottom, 1)
                Text(APSDataFormatter.format(inputValue: glucoseDelta, to: .delta))
                    .informationBarEntryStyle()
                    .padding(.bottom, 1)
            }
        }
        .padding(.bottom, -1)
    }
}

struct GlucoseInformationBarView_Previews: PreviewProvider {
    static let data = [
        InformationBarEntryData(label: "COB: ", value: 33, type: .cob),
        InformationBarEntryData(label: "COB: ", value: 33, type: .cob),
        InformationBarEntryData(label: "COB: ", value: 33, type: .cob)
//        InformationBarEntryData(label: "COB: ", type: .cob, value: 33),
    ]
    static var previews: some View {
        GlucoseInformationBarView(data: data, glucoseValue: 5.5, glucoseDelta: -0.2, direction: .fortyFiveDown)
            .preferredColorScheme(.dark)
            .frame(height: 200)
            .padding(.horizontal)
    }
}
