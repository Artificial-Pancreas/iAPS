import SwiftUI

struct DescriptionView<T: View>: ViewModifier {
    let description: T
    let isPresented: Bool
    let alignment: Alignment

    init(isPresented: Bool, alignment: Alignment, @ViewBuilder content: () -> T) {
        self.isPresented = isPresented
        self.alignment = alignment
        description = content()
    }

    func body(content: Content) -> some View {
        content
            .overlay(popupContent())
    }

    @ViewBuilder private func popupContent() -> some View {
        GeometryReader { geometry in
            if isPresented {
                description
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
            }
        }
    }
}

extension View {
    func description<T: View>(
        isPresented: Bool,
        alignment: Alignment = .center,
        @ViewBuilder content: () -> T
    ) -> some View {
        modifier(DescriptionView(isPresented: isPresented, alignment: alignment, content: content))
    }

    func formatDescription() -> some View {
        modifier(DescriptionLayout())
    }
}

struct DescriptionLayout: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.all, 20)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color(.darkerGray) : Color(.gray))
            )
    }
}
