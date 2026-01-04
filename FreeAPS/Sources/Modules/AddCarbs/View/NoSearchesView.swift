import Foundation
import SwiftUI

struct NoSearchesView: View {
    @ObservedObject var state: FoodSearchStateModel

    var body: some View {
        VStack(spacing: 20) {
            // Main capabilities
            VStack(spacing: 12) {
                // Saved Foods Card (always visible)
                Group {
                    if let savedFoods = state.savedFoods, !savedFoods.foodItemsDetailed.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                state.showSavedFoods = true
                            }
                        }) {
                            CapabilityCard(
                                icon: FoodItemSource.database.icon,
                                iconColor: .orange,
                                title: "Saved Foods",
                                description: "Quick access to your frequently used foods",
                                isDisabled: false
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        CapabilityCard(
                            icon: FoodItemSource.database.icon,
                            iconColor: .orange,
                            title: "Saved Foods",
                            description: "No saved foods",
                            isDisabled: true
                        )
                    }
                }

                CapabilityCard(
                    icon: FoodItemSource.aiText.icon,
                    iconColor: .blue,
                    title: "Text Search",
                    description: "Search databases or describe food for AI analysis",
                    isDisabled: false
                )

                // Barcode Scanner Card
                Button(action: {
                    state.foodSearchRoute = .barcodeScanner
                }) {
                    CapabilityCard(
                        icon: FoodItemSource.barcode.icon,
                        iconColor: .blue,
                        title: "Barcode Scanner",
                        description: "Scan packaged foods for nutrition information",
                        isDisabled: false
                    )
                }
                .buttonStyle(.plain)

                // Photo Analysis Card
                Button(action: {
                    state.foodSearchRoute = .camera
                }) {
                    CapabilityCard(
                        icon: "camera.fill",
                        iconColor: .purple,
                        title: "Photo Analysis",
                        description: "Snap a picture for AI-powered nutrition analysis. Long-press to choose from library.",
                        isDisabled: false
                    )
                }
                .buttonStyle(.plain)

                // Manual Entry Card
                Button(action: {
                    state.showManualEntry = true
                }) {
                    CapabilityCard(
                        icon: FoodItemSource.manual.icon,
                        iconColor: .green,
                        title: "Manual Entry",
                        description: "Enter nutrition information manually",
                        isDisabled: false
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Photography tips
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                    Text("Photography Tips")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TipRow(icon: "light.max", text: "Use good lighting for best results")
                    TipRow(icon: "arrow.up.left.and.arrow.down.right", text: "Include the full plate or package in frame")
                    TipRow(icon: "hand.point.up.left.fill", text: "Place a reference object (coin, hand) for scale")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }
}

private struct CapabilityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(isDisabled ? 0.05 : 0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor.opacity(isDisabled ? 0.3 : 1.0))
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isDisabled ? .secondary : .primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(isDisabled ? 0.6 : 1.0))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground).opacity(isDisabled ? 0.5 : 1.0))
        )
    }
}

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
