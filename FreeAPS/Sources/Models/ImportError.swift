import Foundation

struct ImportError: Identifiable {
    let error: String
    let id = UUID()
}
