import SwiftUI

private enum Config {
    static let defaultCornerRadius: CGFloat = 10
}

private struct InformationBarEntryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(Config.defaultCornerRadius)
    }
}

internal extension View {
    func informationBarEntryStyle() -> some View {
        modifier(InformationBarEntryModifier())
    }
}
