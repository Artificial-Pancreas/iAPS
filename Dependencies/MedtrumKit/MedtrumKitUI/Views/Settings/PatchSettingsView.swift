import LoopKitUI
import SwiftUI

struct PatchSettingsView: View {
    @ObservedObject var viewModel: PatchSettingsViewModel
    @State var isEditingMaxHourly = false
    @State var isEditingMaxDaily = false
    @State var isEditingAlarmSetting = false
    @State var isEditingExpirationTimer = false
    @State var isEditingNotificationAfterActivation = false

    var doDirtyCheck = true

    let unitText = LocalizedString("U", comment: "Insulin unit")
    let hourText = LocalizedString("h", comment: "Hour unit")

    var body: some View {
        VStack {
            List {
                Section {
                    sectionItem(
                        title: LocalizedString("Max hourly insulin", comment: "Label for maximum hourly insulin delivery"),
                        isEditing: isEditingMaxHourly,
                        value: $viewModel.maxHourlyInsulin,
                        valueRange: (viewModel.is300u ? Array(0 ... 12) : Array(0 ... 8)).map({ Double($0) * 5 }),
                        formatter: { value in "\(String(format: "%.0f", value)) \(self.unitText)" }
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingMaxHourly.toggle()
                            self.isEditingMaxDaily = false
                            self.isEditingAlarmSetting = false
                            self.isEditingExpirationTimer = false
                            self.isEditingNotificationAfterActivation = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Max daily insulin", comment: "Label for maximum daily insulin delivery"),
                        isEditing: isEditingMaxDaily,
                        value: $viewModel.maxDailyInsulin,
                        valueRange: (viewModel.is300u ? Array(0 ... 54) : Array(0 ... 36)).map({ Double($0) * 5 }),
                        formatter: { value in "\(String(format: "%.0f", value)) \(self.unitText)" }
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingMaxHourly = false
                            self.isEditingMaxDaily.toggle()
                            self.isEditingAlarmSetting = false
                            self.isEditingExpirationTimer = false
                            self.isEditingNotificationAfterActivation = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Alarm setting", comment: "Label for alarm settings"),
                        isEditing: isEditingAlarmSetting,
                        value: $viewModel.alarmSettings,
                        valueRange: viewModel.alarmOptions,
                        formatter: { value in
                            switch value {
                            case 0:
                                return LocalizedString(
                                    "Light, vibrate and, beep",
                                    comment: "Label for alarm options: light, vibrate and beep"
                                )
                            case 1:
                                return LocalizedString("Light and vibrate", comment: "Label for alarm options: light and vibrate")
                            case 2:
                                return LocalizedString("Light and beep", comment: "Label for alarm options: light and beep")
                            case 3:
                                return LocalizedString("Light-only", comment: "Label for alarm options: light")
                            case 4:
                                return LocalizedString("Vibrate and beep", comment: "Label for alarm options: vibrate and beep")
                            case 5:
                                return LocalizedString("Vibrate-only", comment: "Label for alarm options: vibrate")
                            case 6:
                                return LocalizedString("Beep-only", comment: "Label for alarm options: beep")
                            default:
                                return LocalizedString("Silence", comment: "Label for alarm options: none")
                            }
                        }
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingMaxHourly = false
                            self.isEditingMaxDaily = false
                            self.isEditingAlarmSetting.toggle()
                            self.isEditingExpirationTimer = false
                            self.isEditingNotificationAfterActivation = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Patch lifetime", comment: "Label for expiration alarm"),
                        isEditing: isEditingExpirationTimer,
                        value: $viewModel.expirationTimer,
                        valueRange: Array(0 ... 1).map({ Double($0) }),
                        formatter: { value in
                            switch value {
                            case 0:
                                return LocalizedString(
                                    "Use extended lifetime (continue till battery empty)",
                                    comment: "Label for extended lifetime"
                                )
                            default:
                                return LocalizedString("Use normal lifetime (3d 8h)", comment: "Label for normal patch lifetime")
                            }
                        }
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingMaxHourly = false
                            self.isEditingMaxDaily = false
                            self.isEditingAlarmSetting = false
                            self.isEditingExpirationTimer.toggle()
                            self.isEditingNotificationAfterActivation = false
                        }
                    }

                    if viewModel.expirationTimer == 1 {
                        sectionItem(
                            title: LocalizedString(
                                "Notification for expirate patch",
                                comment: "Label for expired patch notification"
                            ),
                            isEditing: isEditingNotificationAfterActivation,
                            value: $viewModel.notificationAfterActivation,
                            valueRange: Array(60 ... 78).map({ Double($0) }),
                            formatter: { value in "\(String(format: "%.0f", value)) \(self.hourText)" }
                        )
                        .onTapGesture {
                            withAnimation {
                                self.isEditingMaxHourly = false
                                self.isEditingMaxDaily = false
                                self.isEditingAlarmSetting = false
                                self.isEditingExpirationTimer = false
                                self.isEditingNotificationAfterActivation.toggle()
                            }
                        }
                    }
                }
            }
            Spacer()
            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .foregroundStyle(.red)
            }
            Button(action: {
                viewModel.save()
            }) {
                if !viewModel.isUpdating {
                    Text(LocalizedString("Continue", comment: "Continue"))
                } else {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                }
            }
            .disabled(doDirtyCheck && !viewModel.isDirty)
            .buttonStyle(ActionButtonStyle())
            .padding([.bottom, .horizontal])
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarTitle(LocalizedString("Patch settings", comment: "Text for patch settings view"))
    }

    @ViewBuilder func sectionItem(
        title: String,
        isEditing: Bool,
        value: Binding<Double>,
        valueRange: [Double],
        formatter: @escaping (Double) -> String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatter(value.wrappedValue))
        }
        .foregroundColor(isEditing ? Color.blue : Color.primary)

        if isEditing {
            ResizeablePicker(
                selection: value,
                data: valueRange,
                formatter: { value in formatter(value) }
            )
            .padding(.horizontal)
        }
    }
}
