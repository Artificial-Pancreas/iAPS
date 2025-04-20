
import Foundation
import UIKit

enum Icon_: String, CaseIterable, Identifiable {
    case primary = "pod_colorful"
    case artficialPancreasPurple
    case text = "iAPS"
    case podBlack = "podTemplateBlack"
    case popWhite = "podTemplateWhite"
    case cyan = "iAPS_Loop_Cyan_Text"
    case podPurple
    case catWithPod
    case catWithPodWhite = "catWithPodWhiteBG"
    case loopWhiteText = "iAPS_Loop_White_Text"
    case loopText = "iAPS_Loop_Text"
    case black = "iAPS_Black_Black"
    case clean = "iAPS_Clean"
    case purple = "iAPS_Purple"
    case glow = "iAPS_Glow_BG"
    case gray = "iAPS_Gray"
    case whiteAndGray = "iAPS_WhiteAndGray"
    case grayAndLoopNoButtons = "iAPS_NoButtons_Gray_White_BG"
    case purpleBG = "iAPS_Purple_BG"
    case whiteBG = "iAPS_White_BG"
    case loop = "iAPS_Loop"
    case pancreasVial
    var id: String { rawValue }

    var preview: String {
        switch self {
        case .primary: "Image 1"
        case .artficialPancreasPurple:
            "Image 2"
        case .text:
            "Image 3"
        case .podBlack:
            "Image 4"
        case .popWhite:
            "Image 5"
        case .cyan:
            "Image 6"
        case .podPurple:
            "Image 7"
        case .catWithPod:
            "Image 8"
        case .catWithPodWhite:
            "Image 9"
        case .loopWhiteText:
            "Image 10"
        case .loopText:
            "Image 11"
        case .black:
            "Image 12"
        case .clean:
            "Image 13"
        case .purple:
            "Image 14"
        case .glow:
            "Image 15"
        case .gray:
            "Image 16"
        case .whiteAndGray:
            "Image 17"
        case .grayAndLoopNoButtons:
            "Image 18"
        case .purpleBG:
            "Image 19"
        case .whiteBG:
            "Image 20"
        case .loop:
            "Image 21"
        case .pancreasVial:
            "Image 22"
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
