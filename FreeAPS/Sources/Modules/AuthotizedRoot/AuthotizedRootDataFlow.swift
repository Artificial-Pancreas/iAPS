import SwiftUI

enum AuthotizedRoot {
    enum Config {
        static let initialTab = 0
    }

    struct Tab: Identifiable {
        let rootScreen: Screen
        let view: AnyView
        let image: Image
        let text: Text

        var id: Int { rootScreen.id }
    }
}

protocol AuthotizedRootProvider: Provider {}
