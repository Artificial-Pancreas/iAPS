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

struct durationButton<T: DurationButton>: View {
    let states: [T]
    @Binding var selectedState: T

    var body: some View {
        HStack {
            ForEach(0 ..< durationState.allCases.count) { index in
                Button {
                    selectedState = states[index]
                } label: {
                    Text(NSLocalizedString(durationState.allCases[index].title, comment: "Duration displayed in statPanel"))
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                .buttonBorderShape(.automatic)
                .controlSize(.regular)
                .buttonStyle(.borderless)
            }
        }.padding(.horizontal, 10)
    }
}
