import SwiftUI

struct PumpView: View {
    @Binding var reservoir: Decimal?
    @Binding var battery: Battery?
    @Binding var name: String
    @Binding var expiresAtDate: Date?
    @Binding var timerDate: Date
    @Binding var timeZone: TimeZone?

    @State var state: Home.StateModel

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
        HStack(spacing: 5) {
            // OmniPods
            if let date = expiresAtDate {
                // Insulin amount (U)
                if let insulin = reservoir {
                    // 120 % due to being non rectangular. +10 because of bottom inserter
                    let amountFraction = 1.0 - (Double(insulin + 10) * 1.2 / 200)
                    if insulin == 0xDEAD_BEEF {
                        podInsulinAmount(portion: amountFraction)
                            .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                            .overlay {
                                if let timeZone = timeZone,
                                   timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                {
                                    ClockOffset(mdtPump: false)
                                }
                                if (concentration.last?.concentration ?? 1) != 1,
                                   !state.settingsManager.settings
                                   .hideInsulinBadge
                                {
                                    NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pod: true)
                                }
                            }
                    } else {
                        HStack(spacing: 0) {
                            Text(
                                reservoirFormatter
                                    .string(from: (insulin * Decimal(concentration.last?.concentration ?? 1)) as NSNumber) ?? ""
                            )
                            Text("U").foregroundStyle(.secondary)
                        }.offset(x: 6)
                        podInsulinAmount(portion: amountFraction)
                            .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                            .overlay {
                                if let timeZone = timeZone,
                                   timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
                                {
                                    ClockOffset(mdtPump: false)
                                }
                                if (concentration.last?.concentration ?? 1) != 1,
                                   !state.settingsManager.settings.hideInsulinBadge
                                {
                                    NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pod: true)
                                }
                            }
                    }
                }
                remainingTime(time: date.timeIntervalSince(timerDate))
                    .font(.pumpFont)
                    .offset(x: -5, y: 0)
            } else if state.pumpName.contains("Omni") {
                Text("No Pod").font(.statusFont).foregroundStyle(.secondary)
                    .offset(x: 0, y: -4)
            }
            // Other pumps
            else if let reservoir = reservoir {
                if (concentration.last?.concentration ?? 1) != 1, !state.settingsManager.settings.hideInsulinBadge {
                    NonStandardInsulin(concentration: concentration.last?.concentration ?? 1, pod: false)
                }
                let amountFraction = 1.0 - (Double(reservoir + 10) * 1.2 / 200)
                if reservoir == 0xDEAD_BEEF {
                    pumpInsulinAmount(portion: amountFraction)
                        .padding(.leading, (concentration.last?.concentration ?? 1) != 1 ? 7 : 0)
                        .overlay {
                            if let timeZone = timeZone, timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                                ClockOffset(mdtPump: true)
                            }
                        }.offset(x: 0, y: expiresAtDate == nil ? -4 : 0)
                } else {
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
                            if let timeZone = timeZone, timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                                ClockOffset(mdtPump: false)
                            }
                        }
                }
            } else {
                Text("No Pump").font(.statusFont).foregroundStyle(.secondary)
                    .offset(x: 0, y: -4)
            }

            // MDT and Dana
            if let battery = battery, !state.pumpName.contains("Omni") {
                let percent = (battery.percent ?? 100) > 80 ? 100 : (battery.percent ?? 100) < 81 &&
                    (battery.percent ?? 100) >
                    60 ? 75 : (battery.percent ?? 100) < 61 && (battery.percent ?? 100) > 40 ? 50 : 25
                Image(systemName: "battery.\(percent)")
                    .resizable()
                    .rotationEffect(.degrees(-90))
                    .frame(maxWidth: 32, maxHeight: 12)
                    .foregroundColor(batteryColor)
                    .offset(y: -0.5)
            }
        }
        .offset(x: 0, y: 5)
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
        guard let battery = battery, let percent = battery.percent else {
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

    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
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

    private var timerColor: Color {
        guard let expisesAt = expiresAtDate else {
            return .gray
        }

        let time = expisesAt.timeIntervalSince(timerDate)

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
            UIImage(imageLiteralResourceName: "pod_reservoir")
                .fillImageUpToPortion(color: .insulin.opacity(0.8), portion: portion)
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
            UIImage(imageLiteralResourceName: "NonOmniPump")
                .fillImageUpToPortion(color: .insulin.opacity(0.8), portion: max(portion, 0.3))
                .resizable()
                .frame(maxWidth: 17, maxHeight: 36)
                .symbolRenderingMode(.palette)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .padding(.bottom, 5)
        }
    }
}
