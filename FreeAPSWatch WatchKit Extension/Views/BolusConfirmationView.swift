import Combine
import SwiftUI

struct BolusConfirmationView: View {
    @EnvironmentObject var state: WatchStateModel

    @State var crownProgress: CGFloat = 100.0
    @State var progress: CGFloat = 0

    private let elementSize: CGFloat = 30

    @State var progressReturn: AnyCancellable?

    @State var done = false

    var body: some View {
        VStack {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: elementSize / 2, style: .circular)
                        .fill(.secondary)
                        .frame(width: elementSize, height: geo.size.height)
                        .opacity(0.2)

                    RoundedRectangle(cornerRadius: elementSize / 2, style: .circular)
                        .fill(Color.insulin)
                        .frame(width: elementSize, height: elementSize + (geo.size.height - elementSize) * progress / 100)
                        .opacity(0.2)

                    Image(systemName: "arrow.right")
                        .resizable()
                        .frame(width: elementSize / 2, height: elementSize / 2)
                        .foregroundColor(.primary)
                        .position(x: geo.size.width - elementSize / 4, y: elementSize / 2)
                        .transition(.opacity)

                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .foregroundColor(.loopGreen)
                            .frame(width: elementSize, height: elementSize)
                            .position(
                                x: geo.size.width / 2,
                                y: elementSize / 2 + ((geo.size.height - elementSize) * progress / 100)
                            )
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .foregroundColor(.insulin)
                            .frame(width: elementSize, height: elementSize)
                            .position(
                                x: geo.size.width / 2,
                                y: elementSize / 2 + ((geo.size.height - elementSize) * progress / 100)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            Button {
                WKInterfaceDevice.current().play(.click)
                state.pendingBolus = nil
                state.isConfirmationBolusViewActive = false
            }
            label: {
                Text("Cancel")
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $crownProgress,
            from: 0.0,
            through: 100.0,
            by: 0.5,
            sensitivity: .high,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownProgress) { _ in
            guard !done else { return }

            progressReturn?.cancel()
            progress = min(max(0, 100 - crownProgress), 100)
            if progress >= 100 {
                success()
            } else {
                progressReturn = Just(())
                    .delay(for: 0.1, scheduler: RunLoop.main)
                    .sink { _ in
                        crownProgress = 100
                        withAnimation {
                            progress = 0
                        }
                    }
            }
        }
    }

    private func success() {
        WKInterfaceDevice.current().play(.success)
        withAnimation {
            done = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            state.enactBolus()
        }
    }
}

struct BolusConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        BolusConfirmationView(progress: 50, done: false).environmentObject(WatchStateModel())
    }
}
