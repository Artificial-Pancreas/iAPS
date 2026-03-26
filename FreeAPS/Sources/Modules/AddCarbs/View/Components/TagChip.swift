import Foundation
import SwiftUI

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isFavorites: Bool {
        tag == FoodTags.favorites
    }

    private var tagColor: Color {
        if isFavorites {
            return Color.purple
        }
        return stableColor(for: tag)
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if isFavorites {
                    // Use SF Symbol for favorites - filled when selected, outline when not
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSelected ? .white : tagColor)
                } else {
                    // Regular text tag
                    Text(tag.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .textCase(.uppercase)
                        .fontDesign(.default)
                        .kerning(0.5)
                        .foregroundColor(isSelected ? .white : colorScheme == .dark ? .white : .primary)
                }
            }
            .opacity(isSelected ? 1.0 : 0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? tagColor.opacity(0.85) : tagColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : tagColor.opacity(colorScheme == .dark ? 0.45 : 0.35),
                        lineWidth: 1.0
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Generates a stable, visually consistent color for a given string
    /// Uses a hash of the string to pick a hue, with perceptually adjusted lightness
    private func stableColor(for string: String) -> Color {
        // Generate a stable hash from the string
        var hash: UInt64 = 5381
        for char in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }

        // Use the hash to generate a hue (0-360 degrees)
        let hue = Double(hash % 360) / 360.0

        // Adjust brightness based on hue to maintain perceptual uniformity
        // Yellows and greens appear brighter, blues and purples appear darker
        // This compensates by adjusting brightness per hue
        let baseSaturation: Double = 0.70
        let baseBrightness: Double = colorScheme == .dark ? 0.70 : 0.65

        // Adjust brightness based on hue to compensate for perceptual differences
        // Blues/purples (240-300°) need to be brighter
        // Yellows/greens (60-180°) need to be darker
        let hueInDegrees = hue * 360
        var brightnessAdjustment: Double = 0

        if hueInDegrees >= 240 && hueInDegrees <= 300 {
            // Blue to purple range - boost brightness
            brightnessAdjustment = 0.15
        } else if hueInDegrees >= 180 && hueInDegrees < 240 {
            // Cyan to blue - moderate boost
            brightnessAdjustment = 0.10
        } else if hueInDegrees >= 60 && hueInDegrees <= 120 {
            // Yellow to green - reduce brightness
            brightnessAdjustment = -0.05
        } else if hueInDegrees > 30 && hueInDegrees < 60 {
            // Orange range - slight reduction
            brightnessAdjustment = -0.02
        }

        let adjustedBrightness = min(1.0, max(0.0, baseBrightness + brightnessAdjustment))

        return Color(hue: hue, saturation: baseSaturation, brightness: adjustedBrightness)
    }
}
