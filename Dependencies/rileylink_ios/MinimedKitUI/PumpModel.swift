//
//  PumpModel.swift
//  MinimedUI
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import MinimedKit


extension UIImage {
    static func pumpImage(in color: PumpColor?, isLargerModel: Bool, isSmallImage: Bool) -> UIImage {
        var nameComponents = [String]()

        nameComponents.append(isLargerModel ? "7xx" : "5xx")

        if isSmallImage {
            nameComponents.append("Small")
        }

        nameComponents.append({ () -> String in
            switch color {
            case .blue?:
                return "Blue"
            case .clear?:
                return "Clear"
            case .purple?:
                return "Purple"
            case .smoke?:
                return "Smoke"
            case .pink?:
                return "Pink"
            case .none:
                return "Outline"
            }
        }())

        let name = nameComponents.joined(separator: " ")
        return UIImage(named: name, in: Bundle(for: MinimedPumpSettingsViewModel.self), compatibleWith: nil)!
    }
}


extension PumpModel {
    func largeImage(in color: PumpColor?) -> UIImage {
        return UIImage.pumpImage(in: color, isLargerModel: reservoirCapacity > 200, isSmallImage: false)
    }

    func smallImage(in color: PumpColor?) -> UIImage {
        return UIImage.pumpImage(in: color, isLargerModel: reservoirCapacity > 200, isSmallImage: true)
    }
}


extension MinimedPumpManagerState {
    var largePumpImage: UIImage {
        return UIImage.pumpImage(in: pumpColor, isLargerModel: pumpModel.reservoirCapacity > 200, isSmallImage: false)
    }

    var smallPumpImage: UIImage {
        return UIImage.pumpImage(in: pumpColor, isLargerModel: pumpModel.reservoirCapacity > 200, isSmallImage: true)
    }
}
