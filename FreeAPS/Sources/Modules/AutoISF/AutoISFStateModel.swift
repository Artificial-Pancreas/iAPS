import SwiftUI

extension AutoISF {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var autoisf: Bool = false
        @Published var autocr: Bool = false
        @Published var enableBGacceleration: Bool = true
        @Published var use_B30 = false

        @Published var autoisf_min: Decimal = 0.8
        @Published var autoisf_max: Decimal = 1.2
        @Published var smbDeliveryRatioBGrange: Decimal = 0
        @Published var smbDeliveryRatioMin: Decimal = 0.5
        @Published var smbDeliveryRatioMax: Decimal = 0.5
        @Published var autoISFhourlyChange: Decimal = 1
        @Published var higherISFrangeWeight: Decimal = 0
        @Published var lowerISFrangeWeight: Decimal = 0
        @Published var postMealISFweight: Decimal = 0
        @Published var bgAccelISFweight: Decimal = 0
        @Published var bgBrakeISFweight: Decimal = 0.10
        @Published var iobThresholdPercent: Decimal = 100

        // B30
        @Published var iTime_Start_Bolus: Decimal = 1.5
        @Published var b30targetLevel: Decimal = 100
        @Published var b30upperLimit: Decimal = 130
        @Published var b30upperdelta: Decimal = 8
        @Published var b30factor: Decimal = 5
        @Published var b30_duration: Decimal = 30

        // Keto Protection
        @Published var ketoProtect: Bool = false
        @Published var variableKetoProtect: Bool = false
        @Published var ketoProtectAbsolut: Bool = false
        @Published var ketoProtectBasalPercent: Decimal = 20
        @Published var ketoProtectBasalAbsolut: Decimal = 0

        // Nighttime settings
        @Published var nightTime = NightTimeConfiguration.default

        // General settings
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() async {
            subscribeSetting(\.autoisf, on: $autoisf) { self.autoisf = $0 }
            subscribeSetting(\.autocr, on: $autocr) { self.autocr = $0 }
            subscribeSetting(\.enableBGacceleration, on: $enableBGacceleration) { self.enableBGacceleration = $0 }
            subscribeSetting(\.smbDeliveryRatioBGrange, on: $smbDeliveryRatioBGrange) { self.smbDeliveryRatioBGrange = $0 }

            subscribeSetting(\.autoisf_min, on: $autoisf_min) { self.autoisf_min = $0 }
            subscribeSetting(\.autoisf_max, on: $autoisf_max) { self.autoisf_max = $0 }
            subscribeSetting(\.smbDeliveryRatioMin, on: $smbDeliveryRatioMin) { self.smbDeliveryRatioMin = $0 }
            subscribeSetting(\.smbDeliveryRatioMax, on: $smbDeliveryRatioMax) { self.smbDeliveryRatioMax = $0 }
            subscribeSetting(\.autoISFhourlyChange, on: $autoISFhourlyChange) { self.autoISFhourlyChange = $0 }
            subscribeSetting(\.higherISFrangeWeight, on: $higherISFrangeWeight) { self.higherISFrangeWeight = $0 }
            subscribeSetting(\.lowerISFrangeWeight, on: $lowerISFrangeWeight) { self.lowerISFrangeWeight = $0 }
            subscribeSetting(\.postMealISFweight, on: $postMealISFweight) { self.postMealISFweight = $0 }
            subscribeSetting(\.bgAccelISFweight, on: $bgAccelISFweight) { self.bgAccelISFweight = $0 }
            subscribeSetting(\.bgBrakeISFweight, on: $bgBrakeISFweight) { self.bgBrakeISFweight = $0 }
            subscribeSetting(\.iobThresholdPercent, on: $iobThresholdPercent) { self.iobThresholdPercent = $0 }

            subscribeSetting(\.use_B30, on: $use_B30) { self.use_B30 = $0 }
            subscribeSetting(\.iTime_Start_Bolus, on: $iTime_Start_Bolus) { self.iTime_Start_Bolus = $0 }
            subscribeSetting(\.b30targetLevel, on: $b30targetLevel) { self.b30targetLevel = $0 }
            subscribeSetting(\.b30upperLimit, on: $b30upperLimit) { self.b30upperLimit = $0 }
            subscribeSetting(\.b30upperdelta, on: $b30upperdelta) { self.b30upperdelta = $0 }
            subscribeSetting(\.b30factor, on: $b30factor) { self.b30factor = $0 }
            subscribeSetting(\.b30_duration, on: $b30_duration) { self.b30_duration = $0 }

            subscribeSetting(\.ketoProtect, on: $ketoProtect) { self.ketoProtect = $0 }
            subscribeSetting(\.variableKetoProtect, on: $variableKetoProtect) { self.variableKetoProtect = $0 }
            subscribeSetting(\.ketoProtectAbsolut, on: $ketoProtectAbsolut) { self.ketoProtectAbsolut = $0 }
            subscribeSetting(\.ketoProtectBasalPercent, on: $ketoProtectBasalPercent) { self.ketoProtectBasalPercent = $0 }
            subscribeSetting(\.ketoProtectBasalAbsolut, on: $ketoProtectBasalAbsolut) { self.ketoProtectBasalAbsolut = $0 }
            subscribeSetting(\.nightTime, on: $nightTime) { self.nightTime = $0 }

            subscribeSetting(\.units, on: $units) { self.units = $0 }
        }
    }
}
