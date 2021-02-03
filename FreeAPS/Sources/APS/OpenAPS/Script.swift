import Foundation

struct Script {
    let name: String
    let body: String

    init(name: String) {
        self.name = name
        body = try! String(contentsOf: Bundle.main.url(forResource: "javascript/\(name)", withExtension: "js")!)
    }
}
