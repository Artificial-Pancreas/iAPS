import SwiftUI

struct PumpView: View {
    @Binding var reservoir: Decimal?
    @Binding var battery: Battery?
    @Binding var name: String
    @Binding var expiresAtDate: Date?
    @Binding var timerDate: Date

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
            if let battery = battery, expiresAtDate == nil {
                let percent = (battery.percent ?? 100) > 80 ? 100 : (battery.percent ?? 100) < 81 &&
                    (battery.percent ?? 100) >
                    60 ? 75 : (battery.percent ?? 100) < 61 && (battery.percent ?? 100) > 40 ? 50 : 25
                Image(systemName: "battery.\(percent)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 15)
                    .foregroundColor(batteryColor)
            }

            if let reservoir = reservoir {
                let fill = CGFloat(min(max(Double(reservoir) / 200.0, 0.15), Double(reservoir) / 200.0, 0.9)) * 12
                HStack {
                    Image("vial")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 10)
                        .foregroundColor(reservoirColor)
                        .offset(x: 0, y: -3)
                        .overlay {
                            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 2, bottomTrailing: 2))
                                .fill(Color.insulin)
                                .frame(maxWidth: 8.8, maxHeight: fill)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .offset(x: -0.09, y: -3.22)
                        }
                    if reservoir == 0xDEAD_BEEF {
                        HStack(spacing: 0) {
                            Text("50+ ").font(.statusFont).bold()
                            Text(NSLocalizedString("U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 0) {
                            Text(
                                reservoirFormatter
                                    .string(from: reservoir as NSNumber)!
                            ).font(.statusFont).bold()
                            Text(NSLocalizedString(" U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                        }
                    }
                }.offset(x: 0, y: 4)
            } else {
                Text("No Pump").font(.statusFont).foregroundStyle(.secondary)
            }

            if let date = expiresAtDate {
                HStack(spacing: 2) {
                    Image("pod_reservoir")
                        .resizable(resizingMode: .stretch)
                        .frame(width: IAPSconfig.iconSize * 1.15, height: IAPSconfig.iconSize * 1.6)
                        .foregroundColor(colorScheme == .dark ? .secondary : .white)
                    remainingTime(time: date.timeIntervalSince(timerDate))
                        .font(.pumpFont)
                }
            }
        }
    }

    private func remainingTime(time: TimeInterval) -> some View {
        VStack {
            if time > 0 {
                let days = Int(time / 1.days.timeInterval)
                let hours = Int(time / 1.hours.timeInterval)
                let minutes = Int(time / 1.minutes.timeInterval)
                if days >= 1 {
                    HStack(spacing: 0) {
                        Text(" \(days)").foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
                        Text(NSLocalizedString("d", comment: "abbreviation for days"))
                    }
                    HStack(spacing: 0) {
                        Text(" \(hours - days * 24)")
                        Text(NSLocalizedString("h", comment: "abbreviation for hours"))
                    }
                } else if hours >= 1 {
                    HStack(spacing: 0) {
                        Text("\(hours)").foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
                        Text(NSLocalizedString("h", comment: "abbreviation for hours"))
                            .foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
                    }.offset(x: 0, y: 6)
                } else {
                    HStack(spacing: 0) {
                        Text(" \(minutes)").foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
                        Text(NSLocalizedString("m", comment: "abbreviation for minutes"))
                            .foregroundStyle(time < 4 * 60 * 60 ? .red : .primary)
                    }.offset(x: 0, y: 6)
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
