import SwiftUI

struct HoursPickerView: View {
    @Binding var selectedHour: Int
    private let avaliableHours = [1, 3, 6, 12]

    var body: some View {
        Picker("Show Hours", selection: $selectedHour) {
            ForEach(avaliableHours, id: \.self) { hour in
                Text(String(hour) + "HR")
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
}
