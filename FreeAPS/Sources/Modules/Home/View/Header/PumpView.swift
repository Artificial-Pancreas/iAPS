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
        HStack {
            if let reservoir = reservoir {
                HStack {
                    Image(systemName: "cross.vial")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 18)
                        .foregroundColor(reservoirColor)
                    if reservoir == 0xDEAD_BEEF {
                        Text("50+ " + NSLocalizedString("U", comment: "Insulin unit")).font(.statusFont).bold()
                    } else {
                        Text(
                            reservoirFormatter
                                .string(from: reservoir as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
                        )
                        .font(.statusFont).bold()
                    }
                }.padding(.leading, 20)
            }

            if let battery = battery, battery.display ?? false, expiresAtDate == nil {
                let percent = (battery.percent ?? 100) > 80 ? 100 : (battery.percent ?? 100) < 81 && (battery.percent ?? 100) >
                    60 ? 75 : (battery.percent ?? 100) < 61 && (battery.percent ?? 100) > 40 ? 50 : 25
                HStack {
                    Image(systemName: "battery.\(percent)")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 15)
                        .foregroundColor(batteryColor)
                }.padding(.leading, 20)
            }

            if let date = expiresAtDate {
                HStack {
                    Image(systemName: "timer")
                        .resizable()
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, timerColor)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 18)

                    let timeLeft = date.timeIntervalSince(timerDate)
                    Text(remainingTimeString(time: date.timeIntervalSince(timerDate))).font(.statusFont).fontWeight(.bold)
                        .foregroundColor(timeLeft < 4 * 60 * 60 ? .red : .primary)
                }.padding(.leading, 20)
            }
        } // .padding(.horizontal)
    }

    private func remainingTimeString(time: TimeInterval) -> String {
        guard time > 0 else {
            return NSLocalizedString("Replace pod", comment: "View/Header when pod expired")
        }

        var time = time
        let days = Int(time / 1.days.timeInterval)
        time -= days.days.timeInterval
        let hours = Int(time / 1.hours.timeInterval)
        time -= hours.hours.timeInterval
        let minutes = Int(time / 1.minutes.timeInterval)

        if days >= 1 {
            return "\(days)" + NSLocalizedString("d", comment: "abbreviation for days") + " \(hours)" +
                NSLocalizedString("h", comment: "abbreviation for hours")
        }

        if hours >= 1 {
            return "\(hours)" + NSLocalizedString("h", comment: "abbreviation for hours")
        }

        return "\(minutes)" + NSLocalizedString("m", comment: "abbreviation for minutes")
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

struct Hairline: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: UIScreen.main.bounds.width / 1.3, height: 1)
            .opacity(0.5)
    }
}
