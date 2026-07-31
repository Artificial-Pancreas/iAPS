import SwiftUI

struct FemaleBodyThemeView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.pink.opacity(0.15), Color.purple.opacity(0.15)], startPoint: .top, endPoint: .bottom)
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

#Preview("Female body theme") {
    FemaleBodyThemeView()
        .frame(width: 240, height: 360)
}
