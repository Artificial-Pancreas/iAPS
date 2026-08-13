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
            if isMale {
                LinearGradient(colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ZStack {
                    MannequinArmShape(isRight: false)
                        .fill(Color.white.opacity(0.15))
                    MannequinArmShape(isRight: true)
                        .fill(Color.white.opacity(0.15))

                    MannequinTorsoShape()
                        .fill(
                            .linearGradient(
                                colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            MannequinTorsoShape()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                .shadow(color: .cyan.opacity(0.2), radius: 6, x: 0, y: 4)
                        )
                }
                .padding(32)
            } else {
                LinearGradient(
                    colors: [Color.pink.opacity(0.15), Color.purple.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ZStack {
                    FemaleMannequinArmShape(isRight: false)
                        .fill(Color.white.opacity(0.15))
                    FemaleMannequinArmShape(isRight: true)
                        .fill(Color.white.opacity(0.15))

                    FemaleMannequinTorsoShape()
                        .fill(
                            .linearGradient(
                                colors: [Color.pink.opacity(0.9), Color.purple.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            FemaleMannequinTorsoShape()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                .shadow(color: .purple.opacity(0.2), radius: 6, x: 0, y: 4)
                        )
                }
                .padding(32)
            }
        }
    }
}

#Preview("Female body theme") {
    FemaleBodyThemeView(sexSetting: 0)
        .frame(width: 240, height: 360)
}

#Preview("Male body theme") {
    FemaleBodyThemeView(sexSetting: 1)
        .frame(width: 240, height: 360)
}
