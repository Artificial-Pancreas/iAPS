import Foundation
import SwiftUI

enum FoodTags {
    static let favorites = "⭐️"
}

struct FoodTagCloudView: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        // Wrapping tag layout using FlowLayout
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(
                    tag: tag,
                    isSelected: selectedTags.contains(tag),
                    onTap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .center).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .center).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: tag)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: tags)
    }
}

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
            // Use a fixed-size container with overlay to prevent width changes
            Text(isFavorites ? tag : tag.uppercased())
//                .font(.system(size: isFavorites ? 18 : 11, weight: .semibold, design: .default))
                .font(.system(size: 11, weight: .semibold, design: .default))
                .textCase(isFavorites ? nil : .uppercase)
                .fontDesign(.default)
                .kerning(isFavorites ? 0 : 0.5)
                .foregroundColor(isSelected ? .white : colorScheme == .dark ? .white : .primary)
                .opacity(isSelected ? 1.0 : 0.85) // Subtle opacity change instead of weight change
//                .padding(.horizontal, isFavorites ? 8 : 10)
//                .padding(.vertical, isFavorites ? 6 : 5)
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

struct CollapsibleTagsSection: View {
    @Binding var selectedTags: Set<String>
    let allExistingTags: Set<String>
    @Binding var showingAddNewTag: Bool

    @State private var isExpanded: Bool = false

    // Get non-favorite tags (favorites is handled separately)
    private var nonFavoriteTags: [String] {
        var tags = selectedTags.union(allExistingTags)
        tags.remove(FoodTags.favorites)
        return Array(tags).sorted()
    }

    // Count of selected non-favorite tags
    private var selectedNonFavoriteCount: Int {
        selectedTags.filter { $0 != FoodTags.favorites }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button to expand/collapse
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))

                    Text("Tags")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    if selectedNonFavoriteCount > 0 {
                        Text("(\(selectedNonFavoriteCount))")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Tags cloud
                    FlowLayout(spacing: 6) {
                        ForEach(nonFavoriteTags, id: \.self) { tag in
                            TagChip(
                                tag: tag,
                                isSelected: selectedTags.contains(tag),
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedTags.contains(tag) {
                                            selectedTags.remove(tag)
                                        } else {
                                            selectedTags.insert(tag)
                                        }
                                    }
                                }
                            )
                        }

                        // Add new tag button at the end of the flow
                        Button(action: {
                            showingAddNewTag = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("New")
                                    .font(.system(size: 11, weight: .semibold))
                                    .textCase(.uppercase)
                                    .kerning(0.5)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.blue.opacity(0.35), lineWidth: 1.0)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
}

struct TagEditorView: View {
    @Binding var selectedTags: Set<String>
    let allExistingTags: Set<String>

    // Combine selected tags and existing tags, with favorites always first
    private var allTags: [String] {
        var tags = selectedTags.union(allExistingTags)
        // Always include favorites in the list
        tags.insert(FoodTags.favorites)

        var result = Array(tags)
        // Sort so favorites comes first, then alphabetically
        result.sort { tag1, tag2 in
            if tag1 == FoodTags.favorites { return true }
            if tag2 == FoodTags.favorites { return false }
            return tag1 < tag2
        }
        return result
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(allTags, id: \.self) { tag in
                TagChip(
                    tag: tag,
                    isSelected: selectedTags.contains(tag),
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                    }
                )
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth, currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))

                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}
