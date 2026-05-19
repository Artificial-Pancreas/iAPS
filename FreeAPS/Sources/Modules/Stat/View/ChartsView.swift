import SwiftUI

// Extension for Collection.mostFrequent used by other parts of the app
extension Collection {
    func mostFrequent() -> Element? where Element: Hashable {
        reduce(into: [:]) { $0[$1, default: 0] += 1 }.max(by: { $0.1 < $1.1 })?.key
    }
}
