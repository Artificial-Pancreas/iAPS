import SwiftUI
import Swinject

protocol BaseView: View {
    associatedtype StateModelType: StateModel
    var resolver: Resolver { get }
    var state: StateModelType { get }
    var router: Router { get }
//    func configureView()
//    func configureView(_ configure: (() -> Void)?)
}

extension BaseView {
    var router: Router { resolver.resolve(Router.self)! }
}

//
// extension BaseView {
//    func configureView() {
//        configureView(nil)
//    }
//
//    func configureView(_ configure: (() -> Void)?) {
//        print("configureView for \(self)")
//        if state.isInitial {
//            configure?()
//            print("setting state.resolver for \(self)")
//            state.resolver = resolver
//            state.isInitial = false
//        }
//    }
// }
