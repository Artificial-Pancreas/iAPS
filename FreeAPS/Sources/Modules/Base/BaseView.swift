import SwiftUI

protocol BaseView: View {
    associatedtype ViewModel: FreeAPS.ViewModel
    var viewModel: ViewModel { get }
    init()
}

extension BaseView {
    init() { self.init() }
}
