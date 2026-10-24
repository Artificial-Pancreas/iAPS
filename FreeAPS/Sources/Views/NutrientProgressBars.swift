import SwiftUI

struct NutrientProgressBar: View {
    let progress: NutrientProgress

    private var normalized: Double {
        min(progress.percent / 100, 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))

                Capsule()
                    .fill(progress.color)
                    .frame(width: geo.size.width * normalized)
            }
        }
        .frame(height: 6)
    }
}
