import SwiftUI

protocol DurationButton: CaseIterable {
    var title: String { get }
}

extension DurationButton where Self: RawRepresentable, RawValue == String {
    var title: String {
        rawValue
    }
}

enum durationState: String, DurationButton {
    case day = "Today"
    case twentyFour = "24 h"
    case week = "Week "
    case month = "Month "
    case total = "All Days"
}

struct durationButton: View {
    @State private var favoriteColor: durationState = .day

    var body: some View {
        VStack {
            Picker("Choose duration for stored glucose", selection: $favoriteColor) {
                Text("Today").tag(durationState.day)
                Text("24 h").tag(durationState.twentyFour)
                Text("Week ").tag(durationState.week)
                Text("Month ").tag(durationState.month)
                Text("All Days").tag(durationState.total)
            }
            .pickerStyle(.segmented)
        }
    }
}
