import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 5)
                .stroke(lineWidth: 2)
                .frame(width: 20, height: 20)
                .cornerRadius(5)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                    }
                }
                .onTapGesture {
                    withAnimation {
                        configuration.isOn.toggle()
                    }
                }
            configuration.label
        }
    }
}
