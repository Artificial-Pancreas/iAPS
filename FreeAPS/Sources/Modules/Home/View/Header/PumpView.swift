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

    var body: some View {
        HStack(spacing: 10) {
            if let reservoir = reservoir {
                if reservoir == 0xDEAD_BEEF {
                    HStack(spacing: 0) {
                        Text("50+ ").font(.statusFont).bold()
                        Text(NSLocalizedString("U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                    }
                    .offset(x: 0, y: expiresAtDate == nil ? -4 : 0)
                } else {
                    HStack(spacing: 0) {
                        Text(
                            reservoirFormatter
                                .string(from: reservoir as NSNumber)!
                        ).font(.statusFont).bold()
                        Text(NSLocalizedString(" U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                    }
                    .offset(x: 0, y: expiresAtDate == nil ? -4 : 0)
                }
            } else {
                Text("No Pump").font(.statusFont).foregroundStyle(.secondary)
                    .offset(x: 0, y: -4)
            }

            if let battery = battery, !state.pumpName.contains("Omni") {
                let percent = (battery.percent ?? 100) > 80 ? 100 : (battery.percent ?? 100) < 81 &&
                    (battery.percent ?? 100) >
                    60 ? 75 : (battery.percent ?? 100) < 61 && (battery.percent ?? 100) > 40 ? 50 : 25
                Image(systemName: "battery.\(percent)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 15)
                    .foregroundColor(batteryColor)
                    .offset(x: 0, y: -4)
                    .overlay {
                        if let timeZone = timeZone, timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                            ClockOffset(mdtPump: true)
                        }
                    }
            }

            if let date = expiresAtDate {
                Image("pod_reservoir")
                    .resizable(resizingMode: .stretch)
                    .frame(width: IAPSconfig.iconSize * 1.15, height: IAPSconfig.iconSize * 1.6)
                    .foregroundColor(colorScheme == .dark ? .secondary : .white)
                    .offset(x: 0, y: -5)
                    .overlay {
                        if let timeZone = timeZone, timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                            ClockOffset(mdtPump: false)
                        }
                    }
                remainingTime(time: date.timeIntervalSince(timerDate))
                    .font(.pumpFont)
                    .offset(x: -7, y: 0)
            } else if state.pumpName.contains("Omni") {
                Text("No Pod").font(.statusFont).foregroundStyle(.secondary)
                    .offset(x: 0, y: -4)
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
                if days >= 1 {
                    Text(" \(days)" + NSLocalizedString("d", comment: "abbreviation for days" + "+"))
                } else if hours >= 1 {
                    Text(" \(hours)" + NSLocalizedString("h", comment: "abbreviation for hours"))
                        .foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
                } else {
                    Text(" \(minutes)" + NSLocalizedString("m", comment: "abbreviation for minutes"))
                        .foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
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
}
