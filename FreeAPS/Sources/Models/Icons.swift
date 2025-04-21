
import Foundation
import UIKit

enum Icon_: String, CaseIterable, Identifiable {
    case primary = "appIcon1"
    case appIcon2
    case appIcon3
    case appIcon4
    case appIcon5
    case appIcon6
    case appIcon7
    case appIcon8
    case appIcon9
    case appIcon10
    case appIcon11
    case appIcon12
    case appIcon13
    case appIcon14
    case appIcon15
    case appIcon16
    case appIcon17
    case appIcon18
    case appIcon19
    case appIcon20
    case appIcon21
    case appIcon22
    var id: String { rawValue }

    var preview: String {
        switch self {
        case .primary: "Image 1"
        case .appIcon2: "Image 2"
        case .appIcon3: "Image 3"
        case .appIcon4: "Image 4"
        case .appIcon5: "Image 5"
        case .appIcon6: "Image 6"
        case .appIcon7: "Image 7"
        case .appIcon8: "Image 8"
        case .appIcon9: "Image 9"
        case .appIcon10: "Image 10"
        case .appIcon11: "Image 11"
        case .appIcon12: "Image 12"
        case .appIcon13: "Image 13"
        case .appIcon14: "Image 14"
        case .appIcon15: "Image 15"
        case .appIcon16: "Image 16"
        case .appIcon17: "Image 17"
        case .appIcon18: "Image 18"
        case .appIcon19: "Image 19"
        case .appIcon20: "Image 20"
        case .appIcon21: "Image 21"
        case .appIcon22: "Image 22"
        }
    }
}

class Icons: ObservableObject, Equatable {
    @Published var appIcon: Icon_ = .primary

    static func == (lhs: Icons, rhs: Icons) -> Bool {
        lhs.appIcon == rhs.appIcon
    }

    func setAlternateAppIcon(icon: Icon_) {
        let iconName: String? = (icon != .primary) ? icon.rawValue : nil

        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                print("Failed request to update the app’s icon: \(error)")
            }
        }

        appIcon = icon
    }

    init() {
        let iconName = UIApplication.shared.alternateIconName

        if iconName == nil {
            appIcon = .primary
        } else {
            appIcon = Icon_(rawValue: iconName!)!
        }
    }
}
