import Foundation
import LoopKit

extension UserDefaults {
    enum AIKey: String {
        case claudeAPIKey = "com.loopkit.Loop.claudeAPIKey"
        case openAIAPIKey = "com.loopkit.Loop.openAIAPIKey"
        case googleGeminiAPIKey = "com.loopkit.Loop.googleGeminiAPIKey"
        case textSearchProvider = "com.loopkit.Loop.textSearchProvider"
        case barcodeSearchProvider = "com.loopkit.Loop.barcodeSearchProvider"
        case aiImageProvider = "com.loopkit.Loop.aiImageProvider"
        case preferredLanguage = "com.loopkit.Loop.AIPreferredLanguage"
        case preferredRegion = "com.loopkit.Loop.AIPreferredRegion"
        case nutritionAuthority = "com.loopkit.Loop.AINutritionAuthority"
        case aiProviderStatistics = "com.loopkit.Loop.AIStatistics"
        case alwaysOpenCamera = "com.loopkit.Loop.AlwaysOpenCamera"
    }

    var claudeAPIKey: String {
        get {
            string(forKey: AIKey.claudeAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: AIKey.claudeAPIKey.rawValue)
        }
    }

    var openAIAPIKey: String {
        get {
            string(forKey: AIKey.openAIAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: AIKey.openAIAPIKey.rawValue)
        }
    }

    var googleGeminiAPIKey: String {
        get {
            string(forKey: AIKey.googleGeminiAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: AIKey.googleGeminiAPIKey.rawValue)
        }
    }

    var textSearchProvider: TextSearchProvider {
        get {
            if let str = string(forKey: AIKey.textSearchProvider.rawValue) {
                return TextSearchProvider(rawValue: str) ?? .defaultProvider
            } else {
                return .defaultProvider
            }
        }
        set {
            set(newValue.rawValue, forKey: AIKey.textSearchProvider.rawValue)
        }
    }

    var barcodeSearchProvider: BarcodeSearchProvider {
        get {
            if let str = string(forKey: AIKey.barcodeSearchProvider.rawValue) {
                return BarcodeSearchProvider(rawValue: str) ?? .defaultProvider
            } else {
                return .defaultProvider
            }
        }
        set {
            set(newValue.rawValue, forKey: AIKey.barcodeSearchProvider.rawValue)
        }
    }

    var aiImageProvider: ImageSearchProvider {
        get {
            if let str = string(forKey: AIKey.aiImageProvider.rawValue) {
                return ImageSearchProvider(rawValue: str) ?? .defaultProvider
            } else {
                return .defaultProvider
            }
        }
        set {
            set(newValue.rawValue, forKey: AIKey.aiImageProvider.rawValue)
        }
    }

    var userPreferredLanguageForAI: String? {
        get {
            string(forKey: AIKey.preferredLanguage.rawValue)
        }
        set {
            set(newValue, forKey: AIKey.preferredLanguage.rawValue)
        }
    }

    var userPreferredRegionForAI: String? {
        get {
            string(forKey: AIKey.preferredRegion.rawValue)
        }
        set {
            set(newValue, forKey: AIKey.preferredRegion.rawValue)
        }
    }

    var userPreferredNutritionAuthorityForAI: NutritionAuthority {
        get {
            if let str = string(forKey: AIKey.nutritionAuthority.rawValue) {
                return NutritionAuthority(rawValue: str) ?? .localDefault
            } else {
                return .localDefault
            }
        }
        set {
            set(newValue.rawValue, forKey: AIKey.nutritionAuthority.rawValue)
        }
    }

    var alwaysOpenCamera: Bool {
        get {
            bool(forKey: AIKey.alwaysOpenCamera.rawValue)
        }
        set {
            set(newValue, forKey: AIKey.alwaysOpenCamera.rawValue)
        }
    }
}
