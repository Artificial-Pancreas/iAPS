import Foundation
import SwiftUI

struct FoodTagCloudView: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
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
