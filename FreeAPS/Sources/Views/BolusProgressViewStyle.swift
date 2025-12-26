import SwiftUI

struct BolusProgressViewStyle: View {
    let progress: Decimal
    let amount: Decimal
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var rotation: Double = 0
    @State private var shimmerPhase: CGFloat = -140

    init(
        progress: Decimal,
        amount: Decimal,
        onCancel: @escaping () -> Void
    ) {
        self.progress = progress
        self.amount = amount
        self.onCancel = onCancel
    }

    var body: some View {
        let baseColors: [Color] = [
            colorScheme == .dark ? Color.gray.opacity(0.35) : Color.gray.opacity(0.25),
            colorScheme == .dark ? Color.gray.opacity(0.35) : Color.gray.opacity(0.25),
            Color.insulin.opacity(colorScheme == .dark ? 0.65 : 0.55),
            Color.insilight.opacity(colorScheme == .dark ? 0.65 : 0.55),
            Color.insired.opacity(colorScheme == .dark ? 0.65 : 0.55),
            Color.insipurple.opacity(colorScheme == .dark ? 0.65 : 0.55),
            colorScheme == .dark ? Color.gray.opacity(0.35) : Color.gray.opacity(0.25),
            colorScheme == .dark ? Color.gray.opacity(0.35) : Color.gray.opacity(0.25)
        ]

        let waveColors: [Color] = [
            .clear, .clear,
            Color.insulin.opacity(colorScheme == .dark ? 0.85 : 0.75),
            Color.insilight.opacity(colorScheme == .dark ? 0.85 : 0.75),
            Color.insired.opacity(colorScheme == .dark ? 0.85 : 0.75),
            Color.insipurple.opacity(colorScheme == .dark ? 0.85 : 0.75),
            .clear, .clear
        ]

        let innerFillBlur: CGFloat = colorScheme == .dark ? 16 : 12
        let waveInnerBlur: CGFloat = colorScheme == .dark ? 20 : 16

        let innerFillOpacityDark: CGFloat = 0.15
        let innerFillOpacityLight: CGFloat = 0.18

        let outerHaloLineWidth: CGFloat = 2
        let outerHaloBlur: CGFloat = 6
        let outerHaloOpacityDark: CGFloat = 0.32
        let outerHaloOpacityLight: CGFloat = 0.25

        let waveInnerOpacityDark: CGFloat = 0.45
        let waveInnerOpacityLight: CGFloat = 0.38

        let borderLineWidth: CGFloat = 0.8
        let borderBlur: CGFloat = 0.8
        let borderOpacity: CGFloat = colorScheme == .dark ? 0.4 : 0.5

        let displayText: String = {
            let bolused = amount * progress
            if progress >= 1 {
                return "\(amount.formatted()) U delivered"
            } else {
                return "Bolusing \(bolused.formatted()) U / \(amount.formatted()) U"
            }
        }()

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                // Hintergrund blauer Insulinbalken
                                .fill(
                                    colorScheme == .dark ?
                                        Color(white: 0.4).opacity(0.9) :
                                        Color(white: 0.78).opacity(0.8)
                                )
                                .frame(height: 20)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.insulin,
                                            Color.insulin.opacity(0.9)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(Double(progress)), height: 20)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
                        }
                    }
                    .frame(height: 20)
                }
                .frame(maxWidth: .infinity)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onCancel()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 25))
                        .foregroundColor(
                            progress >= 1 ?
                                Color.gray :
                                Color.insulin
                        )
                        .symbolEffect(.bounce, value: progress)
                        .opacity(progress >= 1 ? 0.7 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
                .fixedSize()
                .disabled(progress >= 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        colorScheme == .dark ?
                            Color(white: 0.25, opacity: 0.9) :
                            Color(white: 0.92, opacity: 0.9)
                    )
            )

            Text(displayText)
                .font(.system(size: 16, weight: .semibold))
                .fontDesign(.rounded)
                .foregroundStyle(colorScheme == .dark ? .primary : Color(white: 0.2))
                .opacity(0.9)
                .overlay {
                    if progress < 1 {
                        Text(displayText)
                            .font(.system(size: 16, weight: .semibold))
                            .fontDesign(.rounded)
                            .foregroundStyle(colorScheme == .dark ? .primary : Color(white: 0.2))
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .black.opacity(0.0), location: 0.0),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .black.opacity(0.0), location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .offset(x: shimmerPhase)
                            )
                    }
                }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    colorScheme == .dark ?
                        Color(white: 0.15, opacity: 0.95) :
                        Color(white: 0.88, opacity: 0.95)
                )
                .background(
                    AngularGradient(
                        gradient: Gradient(colors: baseColors),
                        center: .center,
                        angle: .degrees(rotation)
                    )
                    .blur(radius: innerFillBlur)
                    .opacity(colorScheme == .dark ? innerFillOpacityDark : innerFillOpacityLight)
                    .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                    .mask(RoundedRectangle(cornerRadius: 20))
                )
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: baseColors),
                                center: .center,
                                angle: .degrees(rotation)
                            ),
                            lineWidth: outerHaloLineWidth
                        )
                        .blur(radius: outerHaloBlur)
                        .opacity(colorScheme == .dark ? outerHaloOpacityDark : outerHaloOpacityLight)
                        .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                )
                .background(
                    AngularGradient(
                        gradient: Gradient(colors: waveColors),
                        center: .center,
                        angle: .degrees(rotation)
                    )
                    .blur(radius: waveInnerBlur)
                    .opacity(colorScheme == .dark ? waveInnerOpacityDark : waveInnerOpacityLight)
                    .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                    .mask(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: baseColors),
                                center: .center,
                                angle: .degrees(rotation)
                            ),
                            lineWidth: borderLineWidth
                        )
                        .blur(radius: borderBlur)
                        .opacity(borderOpacity)
                        .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                )
                .overlay(
                    Group {
                        if progress < 1 {
                            TimelineView(.animation) { context in
                                let duration: TimeInterval = 7
                                let t = context.date.timeIntervalSinceReferenceDate
                                let phase = t.truncatingRemainder(dividingBy: duration) / duration
                                let seg: CGFloat = 0.12
                                let start = CGFloat(phase)
                                let end = start + seg

                                ZStack {
                                    RoundedRectangle(cornerRadius: 20)
                                        .inset(by: 1.5)
                                        .trim(from: start, to: min(end, 1))
                                        .stroke(
                                            colorScheme == .dark ? Color.spotlightEffect : Color.insipurple.opacity(0.7),
                                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                        )
                                        .blur(radius: 1)
                                        .opacity(colorScheme == .dark ? 0.3 : 0.4)
                                        .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                                        .allowsHitTesting(false)

                                    RoundedRectangle(cornerRadius: 20)
                                        .inset(by: 1.5)
                                        .trim(from: start, to: min(end, 1))
                                        .stroke(
                                            colorScheme == .dark ? Color.spotlightEffect : Color.insipurple.opacity(0.5),
                                            style: StrokeStyle(
                                                lineWidth: 12,
                                                lineCap: .round
                                            )
                                        )
                                        .blur(radius: 6)
                                        .opacity(colorScheme == .dark ? 0.25 : 0.3)
                                        .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                                        .allowsHitTesting(false)

                                    if end > 1 {
                                        let remainingSeg = end - 1

                                        RoundedRectangle(cornerRadius: 20)
                                            .inset(by: 1.5)
                                            .trim(from: 0, to: remainingSeg)
                                            .stroke(
                                                colorScheme == .dark ? Color.spotlightEffect : Color.insipurple.opacity(0.7),
                                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                            )
                                            .blur(radius: 1)
                                            .opacity(colorScheme == .dark ? 0.3 : 0.4)
                                            .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                                            .allowsHitTesting(false)

                                        RoundedRectangle(cornerRadius: 20)
                                            .inset(by: 1.5)
                                            .trim(from: 0, to: remainingSeg)
                                            .stroke(
                                                colorScheme == .dark ? Color.spotlightEffect : Color.insipurple.opacity(0.5),
                                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                            )
                                            .blur(radius: 6)
                                            .opacity(colorScheme == .dark ? 0.25 : 0.3)
                                            .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                )
        )
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.15),
            radius: colorScheme == .dark ? 10 : 8,
            x: 0,
            y: colorScheme == .dark ? 5 : 3
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }

                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    shimmerPhase = 140
                }
            }
        }
    }
}
