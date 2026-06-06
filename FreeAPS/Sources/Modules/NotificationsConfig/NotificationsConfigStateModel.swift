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
        @Published var liveActivityWatchChart = false
        @Published var liveActivityWatchPredictions = true
        @Published var liveActivityWatchDelta = true
        @Published var liveActivityWatchEventual = true

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

        @Published var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let settings = await settingsManager.settings
            let units = settings.units
            self.units = units

            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { self.glucoseBadge = $0 }
            subscribeSetting(\.glucoseNotificationsAlways, on: $glucoseNotificationsAlways) {
                self.glucoseNotificationsAlways = $0 }
            subscribeSetting(\.useAlarmSound, on: $useAlarmSound) { self.useAlarmSound = $0 }
            subscribeSetting(\.addSourceInfoToGlucoseNotifications, on: $addSourceInfoToGlucoseNotifications) {
                self.addSourceInfoToGlucoseNotifications = $0 }
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { self.useLiveActivity = $0 }
            subscribeSetting(\.liveActivityChart, on: $liveActivityChart) { self.liveActivityChart = $0 }
            subscribeSetting(\.liveActivityChartShowPredictions, on: $liveActivityChartShowPredictions) {
                self.liveActivityChartShowPredictions = $0 }
            subscribeSetting(\.liveActivityWatchChart, on: $liveActivityWatchChart) { self.liveActivityWatchChart = $0 }
            subscribeSetting(\.liveActivityWatchPredictions, on: $liveActivityWatchPredictions) {
                self.liveActivityWatchPredictions = $0 }
            subscribeSetting(\.liveActivityWatchDelta, on: $liveActivityWatchDelta) { self.liveActivityWatchDelta = $0 }
            subscribeSetting(\.liveActivityWatchEventual, on: $liveActivityWatchEventual) { self.liveActivityWatchEventual = $0 }
            subscribeSetting(\.lowAlert, on: $lowAlert) { self.lowAlert = $0 }
            subscribeSetting(\.highAlert, on: $highAlert) { self.highAlert = $0 }
            subscribeSetting(\.ascendingAlert, on: $ascendingAlert) { self.ascendingAlert = $0 }
            subscribeSetting(\.descendingAlert, on: $descendingAlert) { self.descendingAlert = $0 }
            subscribeSetting(\.carbsRequiredAlert, on: $carbsRequiredAlert) { self.carbsRequiredAlert = $0 }
            subscribeSetting(\.lowGlucose, on: $lowGlucose, initial: {
                let value = max(min($0, 400), 40)
                self.lowGlucose = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.highGlucose, on: $highGlucose, initial: {
                let value = max(min($0, 400), 40)
                self.highGlucose = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(
                \.carbsRequiredThreshold,
                on: $carbsRequiredThreshold
            ) { self.carbsRequiredThreshold = $0 }

            subscribeSetting(\.hypoSound, on: $hypoSound) { self.hypoSound = $0 }
            subscribeSetting(\.hyperSound, on: $hyperSound) { self.hyperSound = $0 }
            subscribeSetting(\.ascending, on: $ascending) { self.ascending = $0 }
            subscribeSetting(\.descending, on: $descending) { self.descending = $0 }
            subscribeSetting(\.carbSound, on: $carbSound) { self.carbSound = $0 }
            subscribeSetting(\.missingLoops, on: $missingLoops) { self.missingLoops = $0 }
            subscribeSetting(\.bolusFailure, on: $bolusFailure) { self.bolusFailure = $0 }
        }
    }
}
