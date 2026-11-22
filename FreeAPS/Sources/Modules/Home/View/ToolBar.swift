import SwiftUI

@available(
    iOS 27.1,
    *
) struct ToolbarEdgeActionBarLayout<Content: View, VerticalBar: View, BottomBar: View>: View {
    // The key is new in the iOS 27.1 SDK; @available does not hide it from the Xcode 26 compiler.
    #if compiler(>=6.4)
        @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    #else
        private let toolbarVerticalEdge: HorizontalEdge? = nil
    #endif

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

extension EnvironmentValues {
    var usesBottomBar: Bool {
        #if compiler(>=6.4)
            if #available(iOS 27.1, *) {
                return toolbarVerticalEdge == nil
            }
        #endif
        return true
    }
}
