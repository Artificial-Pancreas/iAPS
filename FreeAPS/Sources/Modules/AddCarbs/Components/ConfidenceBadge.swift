import SwiftUI

struct ConfidenceBadge: View {
    let level: AIConfidenceLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)
            Text(level.description)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(level.color.opacity(0.2))
        .foregroundColor(level.color)
        .cornerRadius(6)
    }
}
