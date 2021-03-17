import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Binding var suggestion: Suggestion?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack {
            Circle().strokeBorder(color, lineWidth: 6).frame(width: 38, height: 38)
            Spacer()
            if let date = suggestion?.deliverAt {
                Text(dateFormatter.string(from: date)).font(.caption)
            } else {
                Text("--").font(.caption)
            }
        }
    }

    var color: Color {
        guard let lastDate = suggestion?.deliverAt else {
            return Color(UIColor(named: "LoopGrey")!)
        }
        let delta = Date().timeIntervalSince(lastDate)

        if delta <= 5.minutes.timeInterval {
            return Color(UIColor(named: "LoopGreen")!)
        } else if delta <= 10.minutes.timeInterval {
            return Color(UIColor(named: "LoopYellow")!)
        } else {
            return Color(UIColor(named: "LoopRed")!)
        }
    }
}
