import Foundation
import SwiftUI

struct FoodInfoCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color
    let embedIcon: Bool

    init(icon: String, title: String, content: String, color: Color, embedIcon: Bool = false) {
        self.icon = icon
        self.title = title
        self.content = content
        self.color = color
        self.embedIcon = embedIcon
    }

    var body: some View {
        if embedIcon {
            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .center) {
                    color.opacity(0.25)
                        .cornerRadius(12, corners: [.topLeft, .bottomLeft])

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                }
                .frame(width: 40)

                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(color.opacity(0.08))
            .cornerRadius(12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(NSLocalizedString(title, comment: ""), systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.08))
            .cornerRadius(12)
        }
    }
}
