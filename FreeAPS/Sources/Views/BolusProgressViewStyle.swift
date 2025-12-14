//
//  EnhancedBolusProgressBar.swift
//  FreeAPS
//
//  Created by Richard on 06.12.25.
//
import SwiftUI

struct EnhancedBolusProgressBar: View {
    let progress: Decimal
    let amount: Decimal
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            // Textanzeige
            HStack {
                let bolused = amount * progress
                Text("Bolusing")
                    .font(.system(size: 16, weight: .semibold))

                Text("\(bolused.formatted()) U / \(amount.formatted()) U")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(colorScheme == .dark ? .white : .primary)

            // ProgressBar mit Overlay-Button
            ZStack {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Hintergrund
                        Capsule()
                            .fill(
                                colorScheme == .dark ?
                                    Color(white: 0.2) :
                                    Color(white: 0.9)
                            )
                            .frame(height: 24)

                        // Fortschritt
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.insulin,
                                        Color.insulin.opacity(0.8)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(Double(progress)), height: 24)
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 24)
                .frame(width: 260)

                // Pause-Button als Overlay
                if progress > 0 && progress < 1 {
                    Button(action: onCancel) {
                        Image(systemName: "pause.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold))
                            .shadow(radius: 2)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color.insulin.opacity(0.9))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Circle())
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(
                    colorScheme == .dark ?
                        Color(white: 0.15, opacity: 0.95) :
                        Color(white: 0.98, opacity: 0.95)
                )
                .shadow(
                    color: colorScheme == .dark ?
                        Color.black.opacity(0.3) :
                        Color.gray.opacity(0.3),
                    radius: 10,
                    x: 0,
                    y: 5
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(
                    colorScheme == .dark ?
                        Color.gray.opacity(0.3) :
                        Color.gray.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}
