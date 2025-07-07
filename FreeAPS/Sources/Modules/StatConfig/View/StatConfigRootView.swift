import SwiftUI
import Swinject

extension StatConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        let dateRange: ClosedRange<Date> = {
            let calendar = Calendar.current
            let now = Date()

            let year = calendar.component(.year, from: now)
            let month = calendar.component(.month, from: now)
            let day = calendar.component(.day, from: now) // Aktuellen Tag hinzufügen
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)

            let startComponents = DateComponents(year: 2025, month: 1, day: 1, hour: 0, minute: 0)
            let endComponents = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute) // Tag ergänzt

            let startDate = calendar.date(from: startComponents)!
            let endDate = calendar.date(from: endComponents)!

            return startDate ... endDate
        }()

        func BarViewOptionConfigurationRawValue(
            topBar: Bool, danaBar: Bool, ttBar: Bool, bottomBar: Bool
        ) -> BarViewOptionConfiguration {
            let activeBars = [
                (topBar, "top"),
                (danaBar, "dana"),
                (ttBar, "tt"),
                (bottomBar, "bottom")
            ].compactMap { $0.0 ? $0.1 : nil }

            let imageName = "bars_" + (activeBars.isEmpty ? "none" : activeBars.joined(separator: "_"))

            return BarViewOptionConfiguration(rawValue: imageName) ?? .none
        }

        @State private var displayedStartTime: String?

        func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }

        func saveSensorStartTime(_ date: Date) {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "sensorStartTime")
        }

        func loadSensorStartTime() -> String? {
            if let savedTime = UserDefaults.standard.value(forKey: "sensorStartTime") as? TimeInterval {
                let savedDate = Date(timeIntervalSince1970: savedTime)
                return formatDate(savedDate)
            }
            return nil
        }

        private func imageName(for option: LightGlowOverlaySelector) -> String {
            switch option {
            case .atriumview: return "Moonlight"
            case .atriumview1: return "FullMoon"
            case .atriumview2: return "MiddaySun"
            case .atriumview3: return "EveningSun"
            case .atriumview4: return "RedSun"
            case .atriumview5: return "NortherLights" }
        }

        private func getDescription(for option: DanaBarOption) -> String {
            switch option {
            case .standard: return "Standard"
            case .standard2: return "Standard 2"
            case .marquee: return "Running Text"
            case .max: return "For Dana User"
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    Image(BarViewOptionConfigurationRawValue(
                        topBar: state.displayExpiration,
                        danaBar: state.danaBar,
                        ttBar: state.tempTargetBar,
                        bottomBar: state.timeSettings
                    ).imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 360, height: 280)
                }
                .frame(width: 360, height: 280)
                .padding(.top, 20)
                .padding(.leading, 110)
                .padding(.bottom, 10)

                GeometryReader { geometry in
                    ScrollView {
                        Form {
                            Section(
                                header: Text("Pump Settings"),
                                footer: Text("Configure pump display options")
                            ) {
                                Toggle("Hide Concentration Badge", isOn: $state.hideInsulinBadge)
                            }

                            Section(
                                header: Text("Bar Selection"),
                                footer: Text("Select the desired bar view")
                            ) {
                                Toggle("Top Bars", isOn: $state.danaBar)

                                if state.danaBar {
                                    Picker("Choose a view", selection: $state.danaBarOption) {
                                        ForEach(DanaBarOption.allCases) { option in
                                            HStack(spacing: 12) {
                                                Image(option.previewImageName)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 60, height: 40)
                                                    .cornerRadius(6)
                                                    .shadow(radius: 2)

                                                VStack(alignment: .leading) {
                                                    Text(option.rawValue)
                                                        .font(.subheadline)
                                                    Text(getDescription(for: option))
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .tag(option.rawValue)
                                        }
                                    }
                                    .pickerStyle(NavigationLinkPickerStyle())

                                    // DanaBar Max specific settings
                                    if state.danaBarOption == DanaBarOption.max.rawValue {
                                        Picker(
                                            "Max Reservoir Insulin Age",
                                            selection: $state.insulinAgeOption
                                        ) {
                                            Text("1 Day").tag("Ein_Tag")
                                            Text("2 Days").tag("Zwei_Tage")
                                            Text("3 Days").tag("Drei_Tage")
                                            Text("4 Days").tag("Vier_Tage")
                                            Text("5 Days").tag("Fuenf_Tage")
                                            Text("6 Days").tag("Sechs_Tage")
                                            Text("7 Days").tag("Sieben_Tage")
                                            Text("8 Days").tag("Acht_Tage")
                                            Text("9 Days").tag("Neun_Tage")
                                            Text("10 Days").tag("Zehn_Tage")
                                        }
                                        .pickerStyle(NavigationLinkPickerStyle())
                                    }

                                    // DanaBar Simple specific settings
                                    if state.danaBarOption == DanaBarOption.standard.rawValue {
                                        Picker(
                                            "Max Reservoir Insulin Age",
                                            selection: $state.insulinAgeOption
                                        ) {
                                            Text("1 Day").tag("Ein_Tag")
                                            Text("2 Days").tag("Zwei_Tage")
                                            Text("3 Days").tag("Drei_Tage")
                                            Text("4 Days").tag("Vier_Tage")
                                            Text("5 Days").tag("Fuenf_Tage")
                                            Text("6 Days").tag("Sechs_Tage")
                                            Text("7 Days").tag("Sieben_Tage")
                                            Text("8 Days").tag("Acht_Tage")
                                            Text("9 Days").tag("Neun_Tage")
                                            Text("10 Days").tag("Zehn_Tage")
                                        }
                                        .pickerStyle(NavigationLinkPickerStyle())
                                    }

                                    // Common settings for all views
                                    if state.danaBarOption == DanaBarOption.standard2.rawValue {
                                        Picker(
                                            "Max Reservoir Insulin Age",
                                            selection: $state.insulinAgeOption
                                        ) {
                                            Text("1 Day").tag("Ein_Tag")
                                            Text("2 Days").tag("Zwei_Tage")
                                            Text("3 Days").tag("Drei_Tage")
                                            Text("4 Days").tag("Vier_Tage")
                                            Text("5 Days").tag("Fuenf_Tage")
                                            Text("6 Days").tag("Sechs_Tage")
                                            Text("7 Days").tag("Sieben_Tage")
                                            Text("8 Days").tag("Acht_Tage")
                                            Text("9 Days").tag("Neun_Tage")
                                            Text("10 Days").tag("Zehn_Tage")
                                        }
                                        .pickerStyle(NavigationLinkPickerStyle())
                                    }

                                    if state.danaBarOption == DanaBarOption.marquee.rawValue {
                                        Picker(
                                            "Max Reservoir Insulin Age",
                                            selection: $state.insulinAgeOption
                                        ) {
                                            Text("1 Day").tag("Ein_Tag")
                                            Text("2 Days").tag("Zwei_Tage")
                                            Text("3 Days").tag("Drei_Tage")
                                            Text("4 Days").tag("Vier_Tage")
                                            Text("5 Days").tag("Fuenf_Tage")
                                            Text("6 Days").tag("Sechs_Tage")
                                            Text("7 Days").tag("Sieben_Tage")
                                            Text("8 Days").tag("Acht_Tage")
                                            Text("9 Days").tag("Neun_Tage")
                                            Text("10 Days").tag("Zehn_Tage")
                                        }
                                        .pickerStyle(NavigationLinkPickerStyle())
                                    }

                                    Picker("Max Cannula Age", selection: $state.cannulaAgeOption) {
                                        Text("1 Day").tag("Ein_Tag")
                                        Text("2 Days").tag("Zwei_Tage")
                                        Text("3 Days").tag("Drei_Tage")
                                        Text("4 Days").tag("Vier_Tage")
                                        Text("5 Days").tag("Fuenf_Tage")
                                    }
                                    .pickerStyle(NavigationLinkPickerStyle())
                                }
                                Toggle("TT Bar", isOn: $state.tempTargetBar)
                                Toggle("Bottom Bar", isOn: $state.timeSettings)
                            }

                            Section(
                                header: Text("Visual Options"),
                                footer: Text("According to your taste")
                            ) {
                                Picker("Background Color", selection: $state.backgroundColorOptionRawValue) {
                                    ForEach(BackgroundColorOption.allCases) { option in
                                        HStack {
                                            Rectangle()
                                                .fill(option.color)
                                                .frame(width: 25, height: 25)
                                                .cornerRadius(4)
                                            Text(option.rawValue)
                                                .font(.caption)
                                        }
                                        .tag(option.rawValue)
                                    }
                                }
                                .pickerStyle(NavigationLinkPickerStyle())

                                Toggle("Chart Backgrounds ⇢ Dark", isOn: $state.chartBackgroundColored)
                                Toggle("3D Look", isOn: $state.button3D)
                                if state.button3D {
                                    Toggle(
                                        "Icons Backgrounds ⇢ Dark",
                                        isOn: $state.button3DBackground
                                    ) }
                                Toggle("Atrium Light", isOn: $state.incidenceOfLight)
                                if state.incidenceOfLight {
                                    Picker("Select your Atrium", selection: $state.lightGlowOverlaySelector) {
                                        ForEach(LightGlowOverlaySelector.allCases) { option in
                                            HStack {
                                                Image(imageName(for: option))
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 30, height: 30)
                                                Text(option.rawValue)
                                                    .font(.caption)
                                            }
                                            .tag(option)
                                        }
                                    }
                                    .pickerStyle(NavigationLinkPickerStyle())
                                }
                                // Toggle("Batterie Anzeige", isOn: $state.batteryIconOption)
                            }
                            Toggle("Always Color Glucose Value (green, yellow etc)", isOn: $state.alwaysUseColors)

                            Section {
                                Text("App Icons").navigationLink(to: .iconConfig, from: self)
                            } header: { Text("Choose your App Icon") }

                            Section(
                                header: Text("Sensor Settings"),
                                footer: Text("Long press for setting new Sensor Start Time")
                            ) {
                                Toggle("Display Sensor Time Remaining", isOn: $state.displayExpiration)
                                if state.displayExpiration {
                                    Picker("Select Sensor Span", selection: $state.sensorAgeDays) {
                                        ForEach(SensorAgeDays.allCases, id: \.self) { sensorAge in
                                            Text(sensorAge.localizedName).tag(sensorAge)
                                        }
                                    }
                                    .pickerStyle(NavigationLinkPickerStyle())
                                    HStack {
                                        DatePicker(
                                            "Select Start Time",
                                            selection: $state.sensorStartTimeDefault,
                                            in: dateRange,
                                            displayedComponents: [.date, .hourAndMinute]
                                        )
                                        .datePickerStyle(.compact)
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        Button(action: {}, label: {
                                            Text("Start New Sensor Time")
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 38)
                                                .foregroundColor(.orange)
                                        })
                                            .buttonStyle(.bordered)
                                            .padding(.top)
                                            .simultaneousGesture(
                                                LongPressGesture(minimumDuration: 1.0) // 1 Sekunde halten
                                                    .onEnded { _ in
                                                        let newStartTime = state
                                                            .sensorStartTimeDefault
                                                        state.sensorStartTime = newStartTime
                                                        state.settingsManager.settings.sensorStartTime = newStartTime

                                                        displayedStartTime = formatDate(newStartTime)
                                                        saveSensorStartTime(newStartTime)

                                                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                                                        impactHeavy.impactOccurred()

                                                        print("New sensor started at: \(newStartTime)")
                                                    }
                                            )
                                        HStack {
                                            Text("Last sensor start time:")
                                                .font(.subheadline)
                                            Spacer()
                                            if let startTime = displayedStartTime {
                                                Text(startTime)
                                                    .font(.subheadline)
                                            }
                                        }
                                        .padding(.top)
                                        .padding(.horizontal)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .onAppear {
                                        displayedStartTime = loadSensorStartTime()
                                    }
                                }
                            }

                            Section(header: Text("Chart settings")) {
                                Toggle("Display Chart X - Grid lines", isOn: $state.xGridLines)
                                Toggle("Display Chart Y - Grid lines", isOn: $state.yGridLines)
                                Toggle("Display Chart Threshold lines for Low and High", isOn: $state.rulerMarks)
                                HStack {
                                    Text("Currently selected chart time")
                                    Spacer()
                                    DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                                    Text("hours").foregroundColor(.white)
                                }
                                Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)
                                Toggle("Use insulin bars", isOn: $state.useInsulinBars)
                                Toggle("Display carb equivalents", isOn: $state.fpus)
                                if state.fpus {
                                    Toggle("Display carb equivalent amount", isOn: $state.fpuAmounts)
                                }
                            }
                            // Toggle("Display Glucose Delta", isOn: $state.displayDelta)

                            Section(header: Text("Button Panel")) {
                                Toggle("Display Temp Targets Button", isOn: $state.useTargetButton)
                                Toggle("Display Profile Override Button", isOn: $state.profileButton)
                                Toggle("Display Meal Button", isOn: $state.carbButton)
                            }

                            Section(header: Text("Statistics settings")) {
                                HStack {
                                    Text("Low")
                                    Spacer()
                                    DecimalTextField("0", value: $state.low, formatter: glucoseFormatter)
                                    Text(state.units.rawValue).foregroundColor(.secondary)
                                }
                                HStack {
                                    Text("High")
                                    Spacer()
                                    DecimalTextField("0", value: $state.high, formatter: glucoseFormatter)
                                    Text(state.units.rawValue).foregroundColor(.secondary)
                                }
                                Toggle("Override HbA1c Unit", isOn: $state.overrideHbA1cUnit)
                            }

                            Section(header: Text("Add Meal View settings")) {
                                Toggle("Skip Bolus screen after carbs", isOn: $state.skipBolusScreenAfterCarbs)
                                Toggle("Display and allow Fat and Protein entries", isOn: $state.useFPUconversion)
                            }
                        }
                        .frame(minHeight: geometry.size.height) // Fix für ScrollView
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .onAppear(perform: configureView)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("UI/UX")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
        }
    }
}
