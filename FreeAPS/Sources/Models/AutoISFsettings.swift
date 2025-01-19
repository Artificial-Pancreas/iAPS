import Foundation

struct AutoISFsettings: JSON, Codable {
    var autoisf: Bool = false
    var smbDeliveryRatioBGrange: Decimal = 0
    var smbDeliveryRatioMin: Decimal = 0.5
    var smbDeliveryRatioMax: Decimal = 0.5
    var autoISFhourlyChange: Decimal = 1
    var higherISFrangeWeight: Decimal = 0
    var lowerISFrangeWeight: Decimal = 0
    var postMealISFweight: Decimal = 0.01
    var enableBGacceleration: Bool = true
    var bgAccelISFweight: Decimal = 0
    var bgBrakeISFweight: Decimal = 0.10
    var iobThresholdPercent: Decimal = 100
    var autoisf_max: Decimal = 1.2
    var autoisf_min: Decimal = 0.8
    var use_B30 = false
    var iTime_Start_Bolus: Decimal = 1.5
    var iTime_target: Decimal = 90
    var b30targetLevel: Decimal = 100
    var b30upperLimit: Decimal = 130
    var b30upperdelta: Decimal = 8
    var b30factor: Decimal = 5
    var b30_duration: Decimal = 30
    var ketoProtect: Bool = false
    var variableKetoProtect: Bool = false
    var ketoProtectBasalPercent: Decimal = 20
    var ketoProtectAbsolut: Bool = false
    var ketoProtectBasalAbsolut: Decimal = 0
    var id: String = UUID().uuidString
}
