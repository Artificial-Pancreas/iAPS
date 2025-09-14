import SwiftUI
import Swinject

protocol BaseView: View {
    associatedtype StateModelType: StateModel
    var resolver: Resolver { get }
    var state: StateModelType { get }
    var router: Router { get }
}

extension BaseView {
    var router: Router { resolver.resolve(Router.self)! }
}
