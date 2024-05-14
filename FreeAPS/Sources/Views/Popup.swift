import SwiftUI

struct Popup<T: View>: ViewModifier {
    let popup: T
    let isPresented: Bool
    let alignment: Alignment
    let direction: Direction
    let type: Animation

    init(isPresented: Bool, alignment: Alignment, direction: Direction, type: Animation, @ViewBuilder content: () -> T) {
        self.isPresented = isPresented
        self.alignment = alignment
        self.direction = direction
        self.type = type
        popup = content()
    }

    func body(content: Content) -> some View {
        content
            .overlay(popupContent())
    }

    @ViewBuilder private func popupContent() -> some View {
        GeometryReader { geometry in
            if isPresented {
                popup
                    .animation(type)
                    .transition(.offset(x: 0, y: direction.offset(popupFrame: geometry.frame(in: .global))))
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
            }
        }
    }
}

private extension GeometryProxy {
    var belowScreenEdge: CGFloat {
        UIScreen.main.bounds.height - frame(in: .global).minY
    }
}

extension Popup {
    enum Direction {
        case top
        case bottom
        case center

        func offset(popupFrame: CGRect) -> CGFloat {
            switch self {
            case .top:
                let aboveScreenEdge = -popupFrame.maxY
                return aboveScreenEdge
            case .bottom:
                let belowScreenEdge = UIScreen.main.bounds.height - popupFrame.minY
                return belowScreenEdge
            case .center:
                return UIScreen.main.bounds.midY
            }
        }
    }
}

extension View {
    func popup<T: View>(
        isPresented: Bool,
        alignment: Alignment = .center,
        direction: Popup<T>.Direction = .bottom,
        type: Animation = .spring,
        @ViewBuilder content: () -> T
    ) -> some View {
        modifier(Popup(isPresented: isPresented, alignment: alignment, direction: direction, type: type, content: content))
    }
}
