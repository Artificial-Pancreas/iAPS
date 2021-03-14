import SwiftUI

private struct InformationBarEntryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(10)
    }
}

extension View {
    func informationBarEntryStyle() -> some View {
        modifier(InformationBarEntryModifier())
    }
}
