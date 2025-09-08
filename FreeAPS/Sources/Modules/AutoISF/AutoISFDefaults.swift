extension AutoISF.StateModel {
    func resetToDefaults() {
        // Bools
        autoisf = true
        enableBGacceleration = true
        // use_B30 = false
        // ketoProtect = false
        // variableKetoProtect = false
        // ketoProtectAbsolut = false

        // Decimals
        autoisf_min = 0.8
        autoisf_max = 1.2
        smbDeliveryRatioBGrange = 0
        smbDeliveryRatioMin = 0.5
        smbDeliveryRatioMax = 0.5
        autoISFhourlyChange = 1
        higherISFrangeWeight = 0
        lowerISFrangeWeight = 0
        postMealISFweight = 0.01
        bgAccelISFweight = 0
        bgBrakeISFweight = 0.10
        iobThresholdPercent = 100

        // iTime_Start_Bolus = 1.5
        // b30targetLevel = 100
        // b30upperLimit = 130
        // b30upperdelta = 8
        // b30factor = 5
        // b30_duration = 30

        // ketoProtectBasalPercent = 20
        // ketoProtectBasalAbsolut = 0

        // Units
        // units = .mgdL
    }
}
