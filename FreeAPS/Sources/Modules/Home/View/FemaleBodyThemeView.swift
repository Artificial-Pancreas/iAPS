import SwiftUI

struct FemaleBodyThemeView: View {
    let sexSetting: Int

    init(sexSetting: Int = 0) {
        self.sexSetting = sexSetting
    }

    private var isMale: Bool {
        sexSetting == 1
    }

    var body: some View {
        ZStack {
            // Card background with a modern, premium look
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: isMale ? [
                            Color.blue.opacity(0.08),
                            Color.cyan.opacity(0.03)
                        ] : [
                            Color.pink.opacity(0.08),
                            Color.purple.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: isMale ? [
                                    Color.blue.opacity(0.15),
                                    Color.cyan.opacity(0.10)
                                ] : [
                                    Color.pink.opacity(0.15),
                                    Color.purple.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Centered illustration
            ZStack {
                // Background Glow Circle (gorgeous backdrop shadow)
                Circle()
                    .fill(isMale ? Color.cyan.opacity(0.12) : Color.purple.opacity(0.12))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)

                // Mannequin
                ZStack {
                    if isMale {
                        // Left Arm (Male)
                        MannequinArmShape(isRight: false)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                MannequinArmShape(isRight: false)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                            )

                        // Right Arm (Male)
                        MannequinArmShape(isRight: true)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                MannequinArmShape(isRight: true)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                            )

                        // Torso (Male)
                        MannequinTorsoShape()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.1, green: 0.45, blue: 0.9),
                                        Color(red: 0.05, green: 0.8, blue: 0.95)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.cyan.opacity(0.4), radius: 12, x: 0, y: 6)
                            .overlay(
                                MannequinTorsoShape()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                    } else {
                        // Left Arm (Female)
                        FemaleMannequinArmShape(isRight: false)
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink.opacity(0.12), Color.purple.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                FemaleMannequinArmShape(isRight: false)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                            )

                        // Right Arm (Female)
                        FemaleMannequinArmShape(isRight: true)
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink.opacity(0.12), Color.purple.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                FemaleMannequinArmShape(isRight: true)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                            )

                        // Torso (Female)
                        FemaleMannequinTorsoShape()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.25, blue: 0.5),
                                        Color(red: 0.6, green: 0.1, blue: 0.95)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.purple.opacity(0.4), radius: 12, x: 0, y: 6)
                            .overlay(
                                FemaleMannequinTorsoShape()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                    }
                }
                .frame(width: 140, height: 160)
            }
            .padding(.vertical, 16)
        }
    }
}

#Preview("Female body theme") {
    FemaleBodyThemeView(sexSetting: 0)
        .frame(width: 320, height: 240)
}

#Preview("Male body theme") {
    FemaleBodyThemeView(sexSetting: 1)
        .frame(width: 320, height: 240)
}
