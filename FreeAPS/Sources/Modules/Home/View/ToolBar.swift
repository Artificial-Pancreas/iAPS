import SwiftUI

@available(
    iOS 27.1,
    *
) struct ToolbarEdgeActionBarLayout<Content: View, VerticalBar: View, BottomBar: View>: View {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    let content: Content
    @ViewBuilder let verticalBar: () -> VerticalBar
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        if let toolbarVerticalEdge {
            if toolbarVerticalEdge == .leading {
                content
                    .safeAreaInset(edge: .leading, spacing: 0) {
                        VStack {
                            Spacer()
                            verticalBar()
                                .padding(.horizontal, 10)
                        }
                    }
            } else {
                content
                    .overlay(alignment: .bottomTrailing) {
                        verticalBar()
                            .padding(.leading, 5)
                            .offset(x: 65, y: -10)
                    }
            }
        } else {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar()
                }
        }
    }
}
