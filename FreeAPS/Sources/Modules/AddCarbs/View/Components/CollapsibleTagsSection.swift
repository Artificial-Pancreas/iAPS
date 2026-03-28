import Foundation
import SwiftUI

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
