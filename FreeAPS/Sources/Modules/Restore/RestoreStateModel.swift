import Foundation
import SwiftUI
import Swinject

extension Restore {
    final class StateModel: BaseStateModel<Provider> {
        let coreData = CoreDataStorage()

        func saveFile(_ file: JSON, filename: String) {
            let s = BaseFileStorage()
            s.save(file, as: filename)
            coreData.saveOnbarding()
        }
    }
}
