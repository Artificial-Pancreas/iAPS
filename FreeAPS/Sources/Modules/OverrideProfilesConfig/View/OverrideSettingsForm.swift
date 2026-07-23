import Foundation
import SwiftUI

extension OverrideProfilesConfig {
    /// The override/preset settings editor, extracted from the main view.
    ///
    /// Purely presentational: it edits an `OverrideForm` through a binding and
    /// reads `context` for units/defaults. It owns no state model and no Save
    /// button — the presenting container owns those (and, for presets, the name
    /// field). Emits bare `Section`s, so a container must place it inside a
    /// `Form`/`List`.
    struct OverrideSettingsForm: View {
        @Binding var form: OverrideForm
        let context: OverrideForm.Context

        @State private var isEditing = false

        private static let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }()

        private static let insulinFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }()

        private var glucoseFormatter: NumberFormatter {
            switch context.units {
            case .mmolL: Self.glucoseFormatterMmol
            case .mgdL: Self.glucoseFormatterMgdl
            }
        }

        private static let glucoseFormatterMmol: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.roundingMode = .halfUp
            return formatter
        }()

        private static let glucoseFormatterMgdl: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.roundingMode = .halfUp
            return formatter
        }()

        private static let higherPrecisionFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        private static let promilleFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 3
            return formatter
        }()

        var body: some View {
            // Insulin Slider
            Section {
                VStack {
                    Spacer()
                    Text(
                        (Self.formatter.string(from: form.percentage as NSNumber) ?? "")
                            + " %"
                    )
                    .foregroundColor(
                        form
                            .percentage >= 130 ? .red :
                            (isEditing ? .orange : .blue)
                    )
                    .font(.largeTitle)
                    let max: Double = context.extendedOverrides ? 400 : 200
                    Slider(
                        value: $form.percentage,
                        in: 10 ... max,
                        step: 1,
                        onEditingChanged: { editing in
                            isEditing = editing
                        }
                    ).accentColor(form.percentage >= 130 ? .red : .blue)
                    Spacer()
                }
            }
            header: { Text("Insulin") }
            footer: {
                Text(
                    "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage."
                )
            }

            // Duration
            Section {
                Toggle(isOn: $form._indefinite) {
                    Text("Enable indefinitely")
                }
                if !form._indefinite {
                    HStack {
                        Text("Duration")
                        DecimalTextField("0", value: $form.duration, formatter: Self.formatter, liveEditing: true)
                        Text("minutes").foregroundColor(.secondary)
                    }
                }
            } header: { Text("Duration") }

            // Target
            Section {
                HStack {
                    Toggle(isOn: $form.override_target) {
                        Text("Override Profile Target")
                    }
                }
                if form.override_target {
                    HStack {
                        Text("Target Glucose")
                        DecimalTextField("0", value: $form.target, formatter: glucoseFormatter, liveEditing: true)
                        Text(context.units.rawValue).foregroundColor(.secondary)
                    }
                }
            } header: { Text("Target") }

            // Advanced Settings
            Section {
                HStack {
                    Toggle(isOn: $form.advancedSettings) {
                        Text("More options")
                    }
                }

                if form.advancedSettings {
                    HStack {
                        Toggle(isOn: $form.smbIsOff) {
                            Text("Disable SMBs")
                        }
                    }
                    if form.smbIsOff {
                        HStack {
                            Toggle(isOn: $form.smbIsAlwaysOff) {
                                Text("Schedule when SMBs are Off")
                            }.disabled(!form.smbIsOff)
                        }
                        if form.smbIsAlwaysOff {
                            HStack {
                                Text("First Hour SMBs are Off (24 hours)")
                                DecimalTextField("0", value: $form.start, formatter: Self.formatter, liveEditing: true)
                                Text("hour").foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Last Hour SMBs are Off (24 hours)")
                                DecimalTextField("0", value: $form.end, formatter: Self.formatter, liveEditing: true)
                                Text("hour").foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack {
                        Toggle(isOn: $form.isfAndCr) {
                            Text("Change ISF and CR and Basal")
                        }
                    }

                    if !form.isfAndCr {
                        HStack {
                            Toggle(isOn: $form.isf) {
                                Text("Change ISF")
                            }
                        }
                        HStack {
                            Toggle(isOn: $form.cr) {
                                Text("Change CR")
                            }
                        }
                        HStack {
                            Toggle(isOn: $form.basal) {
                                Text("Change Basal")
                            }
                        }
                    }
                    HStack {
                        Text("SMB Minutes")
                        DecimalTextField(
                            "0",
                            value: $form.smbMinutes,
                            formatter: Self.formatter,
                            liveEditing: true
                        )
                        Text("minutes").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("UAM SMB Minutes")
                        DecimalTextField(
                            "0",
                            value: $form.uamMinutes,
                            formatter: Self.formatter,
                            liveEditing: true
                        )
                        Text("minutes").foregroundColor(.secondary)
                    }

                    HStack {
                        Toggle(isOn: $form.overrideMaxIOB) {
                            Text("Override Max IOB")
                        }
                    }

                    if form.overrideMaxIOB {
                        HStack {
                            Text("Max IOB")
                            DecimalTextField(
                                "0",
                                value: $form.maxIOB,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                            Text("U").foregroundColor(.secondary)
                        }
                    }

                    // Blank Divider()
                    HStack {}

                    HStack {
                        Toggle(isOn: $form.endWIthNewCarbs) {
                            Text("End the Override with next Meal")
                        }
                    }

                    HStack {
                        Toggle(isOn: $form.glucoseOverrideThresholdActive) {
                            Text("End the Override when Glucose is Trending Up")
                        }
                    }

                    if form.glucoseOverrideThresholdActive {
                        HStack {
                            Text("And when Glucose is higher than")
                            BGTextField(
                                "0",
                                mgdlValue: $form.glucoseOverrideThreshold,
                                units: .constant(context.units),
                                isDisabled: false,
                                liveEditing: true
                            )
                        }
                    }

                    HStack {
                        Toggle(isOn: $form.glucoseOverrideThresholdActiveDown) {
                            Text("End the Override when Glucose is Lower ...")
                        }
                    }

                    if form.glucoseOverrideThresholdActiveDown {
                        HStack {
                            Text("... than")
                            BGTextField(
                                "0",
                                mgdlValue: $form.glucoseOverrideThresholdDown,
                                units: .constant(context.units),
                                isDisabled: false,
                                liveEditing: true
                            )
                        }
                    }
                }
            } header: { Text("Advanced Settings") }

            // Auto ISF
            Section {
                Toggle(isOn: $form.overrideAutoISF) {
                    Text("Override Auto ISF")
                }

                if form.overrideAutoISF {
                    Toggle(isOn: $form.autoISFsettings.autoisf) {
                        Text("Enable Auto ISF")
                    }

                    if form.autoISFsettings.autoisf {
                        Toggle(isOn: $form.autoISFsettings.enableBGacceleration) {
                            Text("Enable BG acceleration")
                        }

                        Toggle(isOn: $form.autoISFsettings.autocr) {
                            Text("Enable Auto CR")
                        }

                        HStack {
                            Text("Auto ISF Min")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.autoisf_min,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("Auto ISF Max")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.autoisf_max,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("SMB Delivery Ratio Minimum")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.smbDeliveryRatioMin,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("SMB Delivery Ratio Maximum")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.smbDeliveryRatioMax,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("SMB Delivery Ratio BG Range")
                            BGTextField(
                                "0",
                                mgdlValue: $form.autoISFsettings.smbDeliveryRatioBGrange,
                                units: .constant(context.units),
                                isDisabled: false,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("Duration Weight")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.autoISFhourlyChange,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("ISF weight for higher BG")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.higherISFrangeWeight,
                                formatter: Self.higherPrecisionFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("ISF weight for lower BG")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.lowerISFrangeWeight,
                                formatter: Self.higherPrecisionFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("ISF weight for postprandial BG rise")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.postMealISFweight,
                                formatter: Self.promilleFormatter, liveEditing: true
                            )
                        }

                        HStack {
                            Text("ISF weight while BG accelerates")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.bgAccelISFweight,
                                formatter: Self.higherPrecisionFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("ISF weight while BG decelerates")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.bgBrakeISFweight,
                                formatter: Self.higherPrecisionFormatter,
                                liveEditing: true
                            )
                        }

                        HStack {
                            Text("Max IOB Threshold Percent")
                            DecimalTextField(
                                "0",
                                value: $form.autoISFsettings.iobThresholdPercent,
                                formatter: Self.insulinFormatter,
                                liveEditing: true
                            )
                        }

                        Toggle(isOn: $form.autoISFsettings.use_B30) {
                            Text("Activate B30")
                        }

                        if form.autoISFsettings.use_B30 {
                            HStack {
                                Text("Minimum Start Bolus size")
                                DecimalTextField(
                                    "0",
                                    value: $form.autoISFsettings.iTime_Start_Bolus,
                                    formatter: Self.insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Target Level for B30 to be enacted")
                                BGTextField(
                                    "0",
                                    mgdlValue: $form.autoISFsettings.b30targetLevel,
                                    units: .constant(context.units),
                                    isDisabled: false,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Upper BG limit")
                                BGTextField(
                                    "0",
                                    mgdlValue: $form.autoISFsettings.b30upperLimit,
                                    units: .constant(context.units),
                                    isDisabled: false,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Upper Delta limit")
                                BGTextField(
                                    "0",
                                    mgdlValue: $form.autoISFsettings.b30upperdelta,
                                    units: .constant(context.units),
                                    isDisabled: false,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("B30 Basal rate increase factor")
                                DecimalTextField(
                                    "0",
                                    value: $form.autoISFsettings.b30factor,
                                    formatter: Self.insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Duration of increased B30 basal rate")
                                DecimalTextField(
                                    "0",
                                    value: $form.autoISFsettings.b30_duration,
                                    formatter: Self.insulinFormatter,
                                    liveEditing: true
                                )
                            }
                        }

                        Toggle(isOn: $form.autoISFsettings.ketoProtect) {
                            Text("Enable Keto Protection")
                        }

                        if form.autoISFsettings.ketoProtect {
                            Toggle(isOn: $form.autoISFsettings.variableKetoProtect) {
                                Text("Variable Keto Protection")
                            }

                            if form.autoISFsettings.variableKetoProtect {
                                HStack {
                                    Text("Safety TBR in %")
                                    DecimalTextField(
                                        "0",
                                        value: $form.autoISFsettings.ketoProtectBasalPercent,
                                        formatter: Self.insulinFormatter,
                                        liveEditing: true
                                    )
                                }
                            } else {
                                Toggle(isOn: $form.autoISFsettings.ketoProtectAbsolut) {
                                    Text("Enable Keto protection with pre-defined TBR")
                                }
                                if form.autoISFsettings.ketoProtectAbsolut {
                                    HStack {
                                        Text("Absolute Safety TBR")
                                        DecimalTextField(
                                            "0",
                                            value: $form.autoISFsettings.ketoProtectBasalAbsolut,
                                            formatter: Self.higherPrecisionFormatter,
                                            liveEditing: true
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            } header: { Text("Auto ISF") }
        }
    }
}
