import Foundation

struct DatabasePumpSettings: JSON {
    let settings: PumpSettings?
    let profile: String?
    /// Insulin concentration factor: 1.0 = U100 (standard), 2.0 = U200, etc.
    let insulinConcentration: Double?
}

struct DatabaseTempTargets: JSON {
    let tempTargets: [TempTarget]
    let profile: String?
}

struct DatabaseContactTrick: JSON {
    let contacts: [ContactTrickEntry]
    let profile: String?
}

struct DatabaseProfileStore: JSON {
    var report = "profiles"
    let units: String
    var enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    var profile: String
}

struct DatabaseStatisticsVersion: JSON, Equatable {
    var created_at: Date
    var Build_Version: String
    var Branch: String
    var id: String?
}

struct DatabasePreferences: JSON {
    let preferences: Preferences?
    let profile: String?
}

struct DatabaseSettings: JSON {
    let settings: FreeAPSSettings?
    let profile: String?
}

struct ProfileList: JSON {
    var profiles: String
}

/// One micronutrient entry on a meal preset. Carries the Micronutrient *definition* (name/type/
/// unit) inline rather than an id, because the restoring device has its own Micronutrient rows —
/// the restore looks the definition up by name and creates it if it's new.
struct MigratedMicronutrient: Codable, Equatable, Sendable {
    var name: String
    var type: String?
    var unit: String?
    var amount: Decimal?
    var per100: Bool?
}

/// A meal preset as backed up.
///
/// Everything past the four macros is Optional, and deliberately so: a backup written by an older
/// build has only `carbs/dish/fat/protein`, and Swift's synthesized `Decodable` throws on a
/// missing key rather than falling back to a property's default value. Optional keeps old backups
/// decoding, and a nil field simply leaves that attribute at its CoreData default on restore.
struct MigratedMeals: Codable, Equatable, Sendable {
    var carbs: Decimal
    var dish: String
    var fat: Decimal
    var protein: Decimal
    var fiber: Decimal?
    var sugars: Decimal?
    var glycemicIndex: Decimal?
    var portionSize: Decimal?
    var per100: Bool?
    var mealUnits: String?
    var standardName: String?
    var standardServing: String?
    var standardServingSize: Decimal?
    var imageURL: String?
    var tags: String?
    var foodID: String?
    var micronutrients: [MigratedMicronutrient]?
}

/// The per-override-preset Auto ISF block, which lives in its own CoreData entity keyed by the
/// preset's id and so wasn't part of the preset payload at all.
///
/// Every field is Optional on purpose. This is a wire format that has to survive version skew in
/// both directions — a backup taken on a build with a different Auto ISF field set must still
/// decode — and since `AutoISFsettings` supplies a default for every property, a missing field
/// just keeps that default.
struct MigratedAutoISF: Codable, Equatable {
    var autoisf: Bool?
    var autocr: Bool?
    var smbDeliveryRatioBGrange: Decimal?
    var smbDeliveryRatioMin: Decimal?
    var smbDeliveryRatioMax: Decimal?
    var autoISFhourlyChange: Decimal?
    var higherISFrangeWeight: Decimal?
    var lowerISFrangeWeight: Decimal?
    var postMealISFweight: Decimal?
    var enableBGacceleration: Bool?
    var bgAccelISFweight: Decimal?
    var bgBrakeISFweight: Decimal?
    var iobThresholdPercent: Decimal?
    var autoisf_max: Decimal?
    var autoisf_min: Decimal?
    var use_B30: Bool?
    var iTime_Start_Bolus: Decimal?
    var iTime_target: Decimal?
    var b30targetLevel: Decimal?
    var b30upperLimit: Decimal?
    var b30upperdelta: Decimal?
    var b30factor: Decimal?
    var b30_duration: Decimal?
    var ketoProtect: Bool?
    var variableKetoProtect: Bool?
    var ketoProtectBasalPercent: Decimal?
    var ketoProtectAbsolut: Bool?
    var ketoProtectBasalAbsolut: Decimal?
    var nightTime: NightTimeConfiguration?

    /// Snapshot a stored Auto ISF row for upload.
    init(_ stored: AutoISFsettings) {
        autoisf = stored.autoisf
        autocr = stored.autocr
        smbDeliveryRatioBGrange = stored.smbDeliveryRatioBGrange
        smbDeliveryRatioMin = stored.smbDeliveryRatioMin
        smbDeliveryRatioMax = stored.smbDeliveryRatioMax
        autoISFhourlyChange = stored.autoISFhourlyChange
        higherISFrangeWeight = stored.higherISFrangeWeight
        lowerISFrangeWeight = stored.lowerISFrangeWeight
        postMealISFweight = stored.postMealISFweight
        enableBGacceleration = stored.enableBGacceleration
        bgAccelISFweight = stored.bgAccelISFweight
        bgBrakeISFweight = stored.bgBrakeISFweight
        iobThresholdPercent = stored.iobThresholdPercent
        autoisf_max = stored.autoisf_max
        autoisf_min = stored.autoisf_min
        use_B30 = stored.use_B30
        iTime_Start_Bolus = stored.iTime_Start_Bolus
        iTime_target = stored.iTime_target
        b30targetLevel = stored.b30targetLevel
        b30upperLimit = stored.b30upperLimit
        b30upperdelta = stored.b30upperdelta
        b30factor = stored.b30factor
        b30_duration = stored.b30_duration
        ketoProtect = stored.ketoProtect
        variableKetoProtect = stored.variableKetoProtect
        ketoProtectBasalPercent = stored.ketoProtectBasalPercent
        ketoProtectAbsolut = stored.ketoProtectAbsolut
        ketoProtectBasalAbsolut = stored.ketoProtectBasalAbsolut
        nightTime = stored.nightTime
    }

    /// Fold the backed-up values onto a fresh `AutoISFsettings`, so anything absent keeps the
    /// app's own default for that setting. `id` is set by the caller to the owning preset's id.
    func asSettings(id: String) -> AutoISFsettings {
        var s = AutoISFsettings()
        if let v = autoisf { s.autoisf = v }
        if let v = autocr { s.autocr = v }
        if let v = smbDeliveryRatioBGrange { s.smbDeliveryRatioBGrange = v }
        if let v = smbDeliveryRatioMin { s.smbDeliveryRatioMin = v }
        if let v = smbDeliveryRatioMax { s.smbDeliveryRatioMax = v }
        if let v = autoISFhourlyChange { s.autoISFhourlyChange = v }
        if let v = higherISFrangeWeight { s.higherISFrangeWeight = v }
        if let v = lowerISFrangeWeight { s.lowerISFrangeWeight = v }
        if let v = postMealISFweight { s.postMealISFweight = v }
        if let v = enableBGacceleration { s.enableBGacceleration = v }
        if let v = bgAccelISFweight { s.bgAccelISFweight = v }
        if let v = bgBrakeISFweight { s.bgBrakeISFweight = v }
        if let v = iobThresholdPercent { s.iobThresholdPercent = v }
        if let v = autoisf_max { s.autoisf_max = v }
        if let v = autoisf_min { s.autoisf_min = v }
        if let v = use_B30 { s.use_B30 = v }
        if let v = iTime_Start_Bolus { s.iTime_Start_Bolus = v }
        if let v = iTime_target { s.iTime_target = v }
        if let v = b30targetLevel { s.b30targetLevel = v }
        if let v = b30upperLimit { s.b30upperLimit = v }
        if let v = b30upperdelta { s.b30upperdelta = v }
        if let v = b30factor { s.b30factor = v }
        if let v = b30_duration { s.b30_duration = v }
        if let v = ketoProtect { s.ketoProtect = v }
        if let v = variableKetoProtect { s.variableKetoProtect = v }
        if let v = ketoProtectBasalPercent { s.ketoProtectBasalPercent = v }
        if let v = ketoProtectAbsolut { s.ketoProtectAbsolut = v }
        if let v = ketoProtectBasalAbsolut { s.ketoProtectBasalAbsolut = v }
        if let v = nightTime { s.nightTime = v }
        s.id = id
        return s
    }
}

struct MigratedOverridePresets: Codable, Equatable {
    var advancedSettings: Bool
    var cr: Bool
    var date: Date
    var duration: Decimal
    // Optional: presets are commonly saved with no emoji (null in the backup), and CoreData's
    // OverridePresets.emoji is itself optional — a non-optional here fails the whole array decode.
    var emoji: String?
    var end: Decimal
    var id: String
    var indefininite: Bool
    var isf: Bool
    var isndAndCr: Bool
    var basal: Bool
    var maxIOB: Decimal
    var name: String
    var overrideMaxIOB: Bool
    var percentage: Double
    var smbAlwaysOff: Bool
    var smbIsOff: Bool
    var smbMinutes: Decimal
    var start: Decimal
    var target: Decimal
    var uamMinutes: Decimal
    // Optional: absent from backups written before the Auto ISF block was carried, and absent for
    // presets that never had one.
    var autoISF: MigratedAutoISF?
}

struct DatabaseMeal: JSON, Equatable {
    var profile: String
    var presets: [MigratedMeals]
}

struct DatabaseOverride: JSON, Equatable {
    var profile: String
    var presets: [MigratedOverridePresets]
}

/// The AI food-search / photo-analysis settings.
///
/// These live in `UserDefaults` (see `UserDefaults+AI.swift`) rather than in
/// `freeaps_settings.json`, which is why they were missing from the backup entirely.
///
/// The provider API keys — Claude, OpenAI, Gemini, USDA — are deliberately NOT in this payload
/// and must not be added to it. They're the user's own billable third-party credentials, and
/// putting them on a backup server turns that server into a credential store; re-entering a key
/// after a restore is a far smaller cost than the blast radius of leaking one. Everything here is
/// Optional so a payload from a build with a different key set still decodes, and so a restore
/// only writes what the backup actually had.
struct MigratedAISettings: Codable, Equatable {
    var textSearchProvider: String?
    var barcodeSearchProvider: String?
    var aiImageProvider: String?
    var aiTextProvider: String?
    var preferredLanguage: String?
    var preferredRegion: String?
    var nutritionAuthority: String?
    var sendSmallerImages: Bool?
    var aiTextSearchByDefault: Bool?
    var aiAddImageCommentByDefault: Bool?
    var aiSavePhotosToLibrary: Bool?
    var aiProgressAnimation: Bool?
}

struct AISettingsDatabase: JSON {
    /// Null when the device has never backed any up — the restore then leaves the defaults alone.
    let settings: MigratedAISettings?
    let profile: String?
}

/// The pump settings a restore reads back: the core `PumpSettings` (DIA / max bolus / max
/// basal) plus the insulin concentration the web side merges into the same stored blob.
struct PumpRestoreConfig {
    let settings: PumpSettings?
    let concentration: Double?
}

/// Raw decode of that blob — every field optional so a partial or older row still decodes.
struct RestoredPumpBlob: Decodable {
    let insulinActionCurve: Decimal?
    let maxBolus: Decimal?
    let maxBasal: Decimal?
    let concentration: Double?

    enum CodingKeys: String, CodingKey {
        case insulinActionCurve = "insulin_action_curve"
        case maxBolus
        case maxBasal
        case concentration
    }
}

/// Outcome of a restore-by-login attempt against the account-token endpoint. The UI maps
/// these to prompts (ask for a 2FA code, flag bad credentials, etc.).
enum AccountLoginError: Error {
    case invalidCredentials
    case twoFactorRequired
    case invalidTwoFactor
    case noDevice
    case unreachable
}

/// Linking this device's token to an existing account: the credential/2FA failures of a login,
/// plus the token-specific outcomes.
enum AccountLinkError: Error {
    case invalidCredentials
    case twoFactorRequired
    case invalidTwoFactor
    case tokenNotFound
    case tokenTaken // linked to a different account
    case invalidToken
    case unreachable
}

/// Creating an account from the app. `message` carries the server's already-friendly text for
/// anything without a dedicated case.
enum AccountRegisterError: Error {
    case emailTaken
    case invalidEmail
    case weakPassword
    case tokenInvalid
    case message(String)
    case unreachable
}

struct AccountTokenResponse: Decodable {
    let token: String
}
