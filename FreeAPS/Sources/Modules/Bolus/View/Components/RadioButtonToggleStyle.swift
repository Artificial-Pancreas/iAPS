import SwiftUI

struct RadioButtonToggleStyle: ToggleStyle {
    func makeBody(configuration: ToggleStyle.Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            HStack {
                Image(systemName: configuration.isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(configuration.isOn ? .blue : .secondary)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
