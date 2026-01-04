import SwiftUI

/// Preference key to communicate dismiss prevention state from child views to sheet presentation
struct DismissPreventionKey: PreferenceKey {
    static var defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

/// View extension for easier use
extension View {
    func preventDismiss(_ shouldPrevent: Bool) -> some View {
        preference(key: DismissPreventionKey.self, value: shouldPrevent)
    }
}
