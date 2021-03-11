import SwiftUI

public struct HoursPickerView: View {
    @Binding var selectedHour: Int
    private let avaliableHours = [1, 3, 6, 12]

    public init(selectedHour: Binding<Int>) {
        _selectedHour = selectedHour
    }

    public var body: some View {
        Picker("Show Hours", selection: $selectedHour) {
            ForEach(avaliableHours, id: \.self) { hour in
                Text(String(hour) + "HR")
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
}
