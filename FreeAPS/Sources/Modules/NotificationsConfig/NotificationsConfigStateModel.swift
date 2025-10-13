import SwiftUI

extension NotificationsConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var glucoseBadge = false
        @Published var glucoseNotificationsAlways = false
        @Published var useAlarmSound = false
        @Published var addSourceInfoToGlucoseNotifications = false
        @Published var lowGlucose: Decimal = 0
        @Published var highGlucose: Decimal = 0
        @Published var carbsRequiredThreshold: Decimal = 0
        @Published var useLiveActivity = false
        @Published var liveActivityChart = false
        @Published var liveActivityChartShowPredictions = true

        @Published var hypoSound: String = "New/Anticipalte.caf"
        @Published var hyperSound: String = "New/Anticipalte.caf"
        @Published var ascending: String = "Silent"
        @Published var descending: String = "Silent"
        @Published var carbSound: String = "New/Anticipalte.caf"
        @Published var bolusFailure: String = "Silent"
        @Published var missingLoops = true

        @Published var lowAlert = true
        @Published var highAlert = true
        @Published var ascendingAlert = true
        @Published var descendingAlert = true
        @Published var carbsRequiredAlert = true

        @Published var alarmSound: String = "New/Anticipalte.caf"

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { glucoseBadge = $0 }
            subscribeSetting(\.glucoseNotificationsAlways, on: $glucoseNotificationsAlways) { glucoseNotificationsAlways = $0 }
            subscribeSetting(\.useAlarmSound, on: $useAlarmSound) { useAlarmSound = $0 }
            subscribeSetting(\.addSourceInfoToGlucoseNotifications, on: $addSourceInfoToGlucoseNotifications) {
                addSourceInfoToGlucoseNotifications = $0 }
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.liveActivityChart, on: $liveActivityChart) { liveActivityChart = $0 }
            subscribeSetting(\.liveActivityChartShowPredictions, on: $liveActivityChartShowPredictions) {
                liveActivityChartShowPredictions = $0 }
            subscribeSetting(\.lowAlert, on: $lowAlert) { lowAlert = $0 }
            subscribeSetting(\.highAlert, on: $highAlert) { highAlert = $0 }
            subscribeSetting(\.ascendingAlert, on: $ascendingAlert) { ascendingAlert = $0 }
            subscribeSetting(\.descendingAlert, on: $descendingAlert) { descendingAlert = $0 }
            subscribeSetting(\.carbsRequiredAlert, on: $carbsRequiredAlert) { carbsRequiredAlert = $0 }
            subscribeSetting(\.lowGlucose, on: $lowGlucose, initial: {
                let value = max(min($0, 400), 40)
                lowGlucose = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.highGlucose, on: $highGlucose, initial: {
                let value = max(min($0, 400), 40)
                highGlucose = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(
                \.carbsRequiredThreshold,
                on: $carbsRequiredThreshold
            ) { carbsRequiredThreshold = $0 }

            subscribeSetting(\.hypoSound, on: $hypoSound) { hypoSound = $0 }
            subscribeSetting(\.hyperSound, on: $hyperSound) { hyperSound = $0 }
            subscribeSetting(\.ascending, on: $ascending) { ascending = $0 }
            subscribeSetting(\.descending, on: $descending) { descending = $0 }
            subscribeSetting(\.carbSound, on: $carbSound) { carbSound = $0 }
            subscribeSetting(\.missingLoops, on: $missingLoops) { missingLoops = $0 }
        }
    }
}
