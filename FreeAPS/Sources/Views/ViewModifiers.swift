import Combine
import SwiftUI

struct RoundedBackground: ViewModifier {
    private let color: Color

    init(color: Color = Color("CapsuleColor")) {
        self.color = color
    }

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                Rectangle()
                    // RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill()
                    .foregroundColor(color)
            )
    }
}

struct CapsulaBackground: ViewModifier {
    private let color: Color

    init(color: Color = Color("CapsuleColor")) {
        self.color = color
    }

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                Rectangle()
                    // Capsule()
                    .fill()
                    .foregroundColor(color)
            )
    }
}

struct CompactSectionSpacing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            return content
                .listSectionSpacing(.compact)
        } else {
            return content }
    }
}

struct ScrollTargetLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            return content
                .scrollTargetLayout()
        } else {
            return content }
    }
}

struct ScrollPositionModifier: ViewModifier {
    @Binding var id: Int?
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            return content
                .scrollPosition(id: $id)
        } else {
            return content }
    }
}

struct AddShadow: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.black
                    .opacity(
                        colorScheme == .dark ? IAPSconfig.shadowOpacity : IAPSconfig.shadowOpacity / IAPSconfig
                            .shadowFraction
                    ),
                radius: colorScheme == .dark ? 3 : 2.5
            )
    }
}

struct RaisedRectangle: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Rectangle().fill(colorScheme == .dark ? .black : .white)
            .frame(height: 1)
            .addShadows()
    }
}

struct TestTube: View {
    let opacity: CGFloat
    let amount: CGFloat
    let colourOfSubstance: Color
    let materialOpacity: CGFloat
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        UnevenRoundedRectangle.testTube
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: .white.opacity(opacity), location: amount),
                        Gradient.Stop(color: colourOfSubstance, location: amount)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                FrostedGlass(opacity: materialOpacity)
            }
            .shadow(
                color: Color.black
                    .opacity(
                        colorScheme == .dark ? IAPSconfig.glassShadowOpacity : IAPSconfig.glassShadowOpacity / IAPSconfig
                            .shadowFraction
                    ),
                radius: colorScheme == .dark ? 2.2 : 3
            )
    }
}

struct FrostedGlass: View {
    let opacity: CGFloat
    var body: some View {
        UnevenRoundedRectangle.testTube
            .fill(.ultraThinMaterial.opacity(opacity))
    }
}

struct ColouredRoundedBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Rectangle()
            // RoundedRectangle(cornerRadius: 15)
            .fill(
                colorScheme == .dark ? .black :
                    Color.white
            )
    }
}

struct ColouredBackground: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Rectangle()
            .fill(
                colorScheme == .dark ? .black :
                    Color.white
            )
    }
}

struct LoopEllipse: View {
    @Environment(\.colorScheme) var colorScheme
    let stroke: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(stroke, lineWidth: colorScheme == .light ? 2 : 1)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white).opacity(colorScheme == .light ? 0.2 : 0.08)
            )
    }
}

struct TimeEllipse: View {
    @Environment(\.colorScheme) var colorScheme
    let characters: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(Color.gray).opacity(colorScheme == .light ? 0.2 : 0.2)
            .frame(width: CGFloat(characters * 7), height: 25)
    }
}

struct HeaderBackground: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Rectangle()
            .fill(colorScheme == .light ? .gray.opacity(IAPSconfig.backgroundOpacity) : Color.header2.opacity(1))
    }
}

struct ClockOffset: View {
    let mdtPump: Bool
    var body: some View {
        ZStack {
            Image(systemName: "clock.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 20)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(.warning))
                .offset(x: 10, y: !mdtPump ? -20 : -13)
        }
    }
}

struct ChartBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(colorScheme == .light ? .gray.opacity(0.05) : .black).brightness(colorScheme == .dark ? 0.05 : 0)
    }
}

private let navigationCache = LRUCache<Screen.ID, AnyView>(capacity: 10)

struct NavigationLazyView: View {
    let build: () -> AnyView
    let screen: Screen

    init(_ build: @autoclosure @escaping () -> AnyView, screen: Screen) {
        self.build = build
        self.screen = screen
    }

    var body: AnyView {
        if navigationCache[screen.id] == nil {
            navigationCache[screen.id] = build()
        }
        return navigationCache[screen.id]!
            .onDisappear {
                navigationCache[screen.id] = nil
            }.asAny()
    }
}

struct Link<T>: ViewModifier where T: View {
    private let destination: () -> T
    let screen: Screen

    init(destination: @autoclosure @escaping () -> T, screen: Screen) {
        self.destination = destination
        self.screen = screen
    }

    func body(content: Content) -> some View {
        NavigationLink(destination: NavigationLazyView(destination().asAny(), screen: screen)) {
            content
        }
    }
}

struct AdaptsToSoftwareKeyboard: ViewModifier {
    @State var currentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, currentHeight).animation(.easeOut(duration: 0.25))
            .edgesIgnoringSafeArea(currentHeight == 0 ? Edge.Set() : .bottom)
            .onAppear(perform: subscribeToKeyboardChanges)
    }

    private let keyboardHeightOnOpening = Foundation.NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
        .map { $0.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! CGRect }
        .map(\.height)

    private let keyboardHeightOnHiding = Foundation.NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
        .map { _ in CGFloat(0) }

    private func subscribeToKeyboardChanges() {
        _ = Publishers.Merge(keyboardHeightOnOpening, keyboardHeightOnHiding)
            .subscribe(on: DispatchQueue.main)
            .sink { height in
                if self.currentHeight == 0 || height == 0 {
                    self.currentHeight = height
                }
            }
    }
}

struct ClearButton: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        HStack {
            content
            if !text.isEmpty {
                Button { self.text = "" }
                label: {
                    Image(systemName: "delete.left")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

extension View {
    func roundedBackground() -> some View {
        modifier(RoundedBackground())
    }

    func addShadows() -> some View {
        modifier(AddShadow())
    }

    func addBackground() -> some View {
        ColouredRoundedBackground()
    }

    func addColouredBackground() -> some View {
        ColouredBackground()
    }

    func addHeaderBackground() -> some View {
        HeaderBackground()
    }

    func chartBackground() -> some View {
        modifier(ChartBackground())
    }

    func frostedGlassLayer(_ opacity: CGFloat) -> some View {
        FrostedGlass(opacity: opacity)
    }

    func navigationLink<V: BaseView>(to screen: Screen, from view: V) -> some View {
        modifier(Link(destination: view.state.view(for: screen), screen: screen))
    }

    func adaptsToSoftwareKeyboard() -> some View {
        modifier(AdaptsToSoftwareKeyboard())
    }

    func modal<V: BaseView>(for screen: Screen?, from view: V) -> some View {
        onTapGesture {
            view.state.showModal(for: screen)
        }
    }

    func compactSectionSpacing() -> some View {
        modifier(CompactSectionSpacing())
    }

    func scrollTargetLayoutiOS17() -> some View {
        modifier(ScrollTargetLayoutModifier())
    }

    func scrollPositioniOS17(id: Binding<Int?>) -> some View {
        modifier(ScrollPositionModifier(id: id))
    }

    func asAny() -> AnyView { .init(self) }
}

extension UnevenRoundedRectangle {
    static let testTube =
        UnevenRoundedRectangle(
            topLeadingRadius: 1.5,
            bottomLeadingRadius: 50,
            bottomTrailingRadius: 50,
            topTrailingRadius: 1.5
        )
}
