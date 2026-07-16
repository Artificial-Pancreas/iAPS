import UIKit

@discardableResult func withBackgroundTask<T>(
    _ name: String,
    extend: Duration? = nil,
    isolation _: isolated(any Actor)? = #isolation,
    _ work: () async throws -> T
) async rethrows -> T {
    let box = TaskIDBox()
    await MainActor.run {
        box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
    }

    @Sendable func end() async {
        await MainActor.run {
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
    }

    do {
        let result = try await work()
        if let extend { try? await Task.sleep(for: extend) }
        await end()
        return result
    } catch {
        if let extend { try? await Task.sleep(for: extend) }
        await end()
        throw error
    }
}
