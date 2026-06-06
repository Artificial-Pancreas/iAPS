import Combine
import Foundation

extension Task {
    // can be used as Task { ... }.store(in: &lifetime)
    func store(in set: inout Set<AnyCancellable>) {
        set.insert(AnyCancellable(cancel))
    }
}
