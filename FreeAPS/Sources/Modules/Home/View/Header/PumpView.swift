import SwiftUI

struct PumpView: View {
    @Environment(AppUIState.self) private var appUIState

    let hideInsulinBadge: Bool
    let timerDate: Date

    @Environment(\.colorScheme) var colorScheme

    private var reservoirFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var batteryFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        return dateFormatter
    }

    @FetchRequest(
        entity: InsulinConcentration.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
    ) var concentration: FetchedResults<InsulinConcentration>

    var body: some View {
        let pumpInfo = appUIState.pumpInfo
        let pumpStatus = appUIState.pumpStatus
        let reservoir = appUIState.pumpReservoir

        let nano = pumpInfo?.name.contains("Medtrum") ?? false
        let omni = pumpInfo?.name.contains("Omni") ?? false
        // let sim = pumpName?.contains("Simulator") ?? false // Just For Testing
        HStack(spacing: 5) {
            // OmniPods and Medtrum nanos
            if let pumpInfo, !pumpInfo.isOnboarded
            {
                Text("Re-connect pump!").font(.statusFont).foregroundStyle(.red)
                    .offset(y: -4)
            } else {
                if let date = pumpInfo?.expiresAt {
                    // Insulin amount (U)
                    if case let .units(insulin) = reservoir {
                        // 120 % due to being non rectangular. +10 because of bottom inserter.
                        let amountFraction = 1.0 - (Double(insulin + 10) * 1.2 / 200)

                        HStack(spacing: 0) {
                            let amount: Decimal = (insulin * Decimal(concentration.last?.concentration ?? 1))
                            Text(reservoirFormatter.string(from: amount as NSNumber) ?? "")
                                .padding(.trailing, 2)
                            Text("U").foregroundStyle(.secondary)
                        }.offset(x: 6)
                        if nano {
                            medtrumInsulinAmount(portion: amountFraction)
                                .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                                .overlay {
                                    if let timeZone = pumpStatus?.timeZone,
                                       timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                    {
                                        ClockOffset(mdtPump: false)
                                    }
                                    if (concentration.last?.concentration ?? 1) != 1,
                                       !hideInsulinBadge
                                    {
                                        NonStandardInsulin(
                                            concentration: concentration.last?.concentration ?? 1,
                                            pump: .medtrum
                                        )
                                    }
                                }
                        } else {
                            podInsulinAmount(portion: amountFraction)
                                .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                                .overlay {
                                    if let timeZone = pumpStatus?.timeZone,
                                       timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                    {
                                        ClockOffset(mdtPump: false)
                                    }
                                    if (concentration.last?.concentration ?? 1) != 1,
                                       !hideInsulinBadge
                                    {
                                        NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pump: .pod)
                                    }
                                }
                        }

                    } else if reservoir == .aboveThreshold {
                        if nano {
                            medtrumInsulinAmount(portion: 0.0)
                                .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                                .overlay {
                                    if let timeZone = pumpStatus?.timeZone,
                                       timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                    {
                                        ClockOffset(mdtPump: false)
                                    }
                                    if (concentration.last?.concentration ?? 1) != 1,
                                       !hideInsulinBadge
                                    {
                                        NonStandardInsulin(
                                            concentration: concentration.last?.concentration ?? 1,
                                            pump: .medtrum
                                        )
                                    }
                                }
                        } else {
                            podInsulinAmount(portion: 0.0)
                                .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                                .overlay {
                                    if let timeZone = pumpStatus?.timeZone,
                                       timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                    {
                                        ClockOffset(mdtPump: false)
                                    }
                                    if (concentration.last?.concentration ?? 1) != 1,
                                       !hideInsulinBadge
                                    {
                                        NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pump: .pod)
                                    }
                                }
                        }
                    } else if pumpInfo != nil {
                        ZStack {}
                            .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                            .overlay {
                                if let timeZone = pumpStatus?.timeZone,
                                   timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                {
                                    ClockOffset(mdtPump: false)
                                }
                                if (concentration.last?.concentration ?? 1) != 1,
                                   !hideInsulinBadge
                                {
                                    NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pump: .pod)
                                }
                            }
                    }

                    remainingTime(time: date.timeIntervalSince(timerDate))
                        .font(.pumpFont)
                        .offset(x: nano ? -8.5 : -5)
                } else if omni {
                    Text("No Pod").font(.statusFont).foregroundStyle(.secondary)
                        .offset(y: -4)
                } else if nano {
                    Text("No Patch").font(.statusFont).foregroundStyle(.secondary)
                        .offset(y: -4)
                }
                // Other pumps
                else if case let .units(reservoir) = reservoir {
                    if (concentration.last?.concentration ?? 1) != 1, !hideInsulinBadge {
                        NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pump: .other)
                    }
                    let amountFraction = 1.0 - (Double(reservoir + 10) * 1.2 / 200)
                    HStack(spacing: 0) {
                        Text(
                            reservoirFormatter
                                .string(from: (reservoir * Decimal(concentration.last?.concentration ?? 1)) as NSNumber) ?? ""
                        ).font(.statusFont)
                        Text("U").font(.statusFont).foregroundStyle(.secondary)
                    }
                    .offset(y: 7)
                    pumpInsulinAmount(portion: amountFraction)
                        .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                        .overlay {
                            if let timeZone = pumpStatus?.timeZone,
                               timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                            {
                                ClockOffset(mdtPump: false)
                            }
                        }
                } else if reservoir == .aboveThreshold {
                    if (concentration.last?.concentration ?? 1) != 1, !hideInsulinBadge {
                        NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pump: .other)
                    }

                    pumpInsulinAmount(portion: 0.0)
                        .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                        .overlay {
                            if let timeZone = pumpStatus?.timeZone,
                               timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                            {
                                ClockOffset(mdtPump: true)
                            }
                        }.offset(y: pumpInfo?.expiresAt == nil ? -4 : 0)
                } else {
                    if pumpInfo != nil {
                        Text("---").font(.statusFont).foregroundStyle(.secondary)
                            .offset(y: -4)
                    } else {
                        Text("No Pump").font(.statusFont).foregroundStyle(.secondary)
                            .offset(y: -4)
                    }
                }

                // MDT and Dana
                if let battery = pumpStatus?.battery, !omni, !nano {
                    let percent = (battery.percent ?? 100) > 80 ? 100 : (battery.percent ?? 100) < 81 &&
                        (battery.percent ?? 100) >
                        60 ? 75 : (battery.percent ?? 100) < 61 && (battery.percent ?? 100) > 40 ? 50 : 25
                    Image(systemName: "battery.\(percent)")
                        .resizable()
                        .rotationEffect(.degrees(-90))
                        .frame(maxWidth: 32, maxHeight: 12)
                        .foregroundColor(batteryColor)
                        .offset(x: -5, y: -0.9)
                        .padding(.bottom, 2)
                }
            }
        }
        .offset(x: (nano && pumpInfo?.expiresAt != nil) ? 5 : 0, y: (nano && pumpInfo?.expiresAt != nil) ? 10 : 5)
    }

    private func remainingTime(time: TimeInterval) -> some View {
        HStack {
            if time > 0 {
                let days = Int(time / 1.days.timeInterval)
                let hours = Int(time / 1.hours.timeInterval)
                let minutes = Int(time / 1.minutes.timeInterval)
                let adjustedHours = Int(hours - days * 24)

                if days >= 1 {
                    HStack(spacing: 0) {
                        Text(" \(days)")
                        Text(NSLocalizedString("d", comment: "abbreviation for days")).foregroundStyle(.secondary)
                        if adjustedHours >= 0 {
                            Text(" ")
                            Text("\(adjustedHours)")
                            // spacer
                            Text(NSLocalizedString("h", comment: "abbreviation for days")).foregroundStyle(.secondary)
                        }
                    }
                } else if hours >= 1 {
                    HStack(spacing: 0) {
                        Text(" \(hours)")
                        Text(NSLocalizedString("h", comment: "abbreviation for hours"))
                            .foregroundStyle(time < 4 * 60 * 60 ? .red : .secondary)
                    }
                } else {
                    HStack(spacing: 0) {
                        Text(" \(minutes)")
                        Text(NSLocalizedString("m", comment: "abbreviation for minutes"))
                            .foregroundStyle(time < 4 * 60 * 60 ? .red : .secondary)
                    }
                }
            } else {
                Text(NSLocalizedString("Replace", comment: "View/Header when pod expired")).foregroundStyle(.red)
            }
        }
    }

    private var batteryColor: Color {
        guard let battery = appUIState.pumpStatus?.battery, let percent = battery.percent else {
            return .gray
        }
        switch percent {
        case ...10:
            return .red
        case ...20:
            return .yellow
        default:
            return .green
        }
    }

    private func reservoirColor(_ reservoir: Decimal?) -> Color {
        guard let reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return .red
        case ...30:
            return .yellow
        default:
            return .blue
        }
    }

    private func timerColor(_ expiresAt: Date?) -> Color {
        guard let expiresAt else {
            return .gray
        }

        let time = expiresAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return .red
        case ...1.days.timeInterval:
            return .yellow
        default:
            return .green
        }
    }

    private func podInsulinAmount(portion: Double) -> some View {
        ZStack {
            let pump = colorScheme == .dark ? "pod_dark" : "pod_light"
            UIImage(imageLiteralResourceName: pump)
                .fillImageUpToPortion(color: insulinColour(portion).opacity(0.8), portion: portion)
                .resizable()
                .aspectRatio(0.72, contentMode: .fit)
                .frame(width: IAPSconfig.iconSize, height: IAPSconfig.iconSize)
                .symbolRenderingMode(.palette)
                .offset(x: 0, y: -5)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .overlay {
                    let units = 50 * (concentration.last?.concentration ?? 1)
                    portion <= 0.3 ?
                        Text((reservoirFormatter.string(from: units as NSNumber) ?? "") + "+").foregroundStyle(.white)
                        .font(.system(size: 6))
                        .offset(y: -4)
                        : nil
                }
        }
    }

    private func pumpInsulinAmount(portion: Double) -> some View {
        ZStack {
            let pump = colorScheme == .dark ? "pump_dark" : "pump_light"
            UIImage(imageLiteralResourceName: pump)
                .fillImageUpToPortion(color: insulinColour(portion).opacity(0.8), portion: max(portion, 0.3))
                .resizable()
                .frame(maxWidth: 17, maxHeight: 36)
                .symbolRenderingMode(.palette)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .padding(.bottom, 5)
        }
    }

    private func medtrumInsulinAmount(portion: Double) -> some View {
        ZStack {
            UIImage(imageLiteralResourceName: "nano")
                .fillImageUpToPortion(color: insulinColour(portion).opacity(0.8), portion: max(portion, 0.3))
                .resizable()
                .aspectRatio(0.7, contentMode: .fit)
                .frame(height: IAPSconfig.iconSize)
                .symbolRenderingMode(.palette)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .padding(5)
                .offset(y: -5)
        }
    }

    private func insulinColour(_ emptyFactor: Double) -> Color {
        emptyFactor > 0.85 ? Color.orange : Color.insulin
    }
}
