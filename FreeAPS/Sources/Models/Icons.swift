
import Foundation
import UIKit

/// The alternate app icons available for this app to use.
///
/// These raw values match the names in the app's project settings under
/// `ASSETCATALOG_COMPILER_APPICON_NAME` and `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
enum Icon_: String, CaseIterable, Identifiable {
    case primary = "iAPS"
    case loopText = "iAPS_Loop_Text"
    case black = "iAPS_Black_Black"
    case clean = "iAPS_Clean"
    case purple = "iAPS_Purple"
    case glow = "iAPS_Glow_BG"
    case gray = "iAPS_Gray"
    case whiteAndGray = "iAPS_WhiteAndGray"
    case grayAndLoop = "iAPS_NoButtons_Gray_White_BG"
    case purpleBG = "iAPS_Purple_BG"
    case whiteBG = "iAPS_White_BG"
    // case pink       = "AppIcon-Pink"
    // case teal       = "AppIcon-Teal"
    // case yellow     = "AppIcon-Yellow"

    var id: String { rawValue }
}

class Icons: ObservableObject, Equatable {
    @Published var appIcon: Icon_ = .primary

    static func == (lhs: Icons, rhs: Icons) -> Bool {
        lhs.appIcon == rhs.appIcon
    }

    /// Change the app icon.
    /// - Tag: setAlternateAppIcon
    func setAlternateAppIcon(icon: Icon_) {
        // Set the icon name to nil to use the primary icon.
        let iconName: String? = (icon != .primary) ? icon.rawValue : nil

        // Avoid setting the name if the app already uses that icon.
        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                print("Failed request to update the app’s icon: \(error)")
            }
        }

        appIcon = icon
    }

    /// Initializes the model with the current state of the app's icon.
    init() {
        let iconName = UIApplication.shared.alternateIconName

        if iconName == nil {
            appIcon = .primary
        } else {
            appIcon = Icon_(rawValue: iconName!)!
        }
    }
}
