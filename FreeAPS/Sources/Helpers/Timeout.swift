import Foundation

struct TimeoutError: LocalizedError {
    let name: String
    let duration: Duration

    var errorDescription: String? {
        "\(name) timed out after \(duration.components.seconds)s"
    }
}

func withTimeout<T: Sendable>(
    _ name: String,
    _ duration: Duration,
    _ work: @escaping @Sendable() async throws -> T
) async throws -> T {
    let race = TimeoutRace<T>()

    return try await withCheckedThrowingContinuation { continuation in
        race.arm(continuation)

        race.setTimer(Task {
            try? await Task.sleep(for: duration)
            race.finish(.failure(TimeoutError(name: name, duration: duration)))
        })

        Task {
            do {
                let value = try await work()
                race.finish(.success(value))
            } catch {
                race.finish(.failure(error))
            }
        }
    }
}

/// Resumes a continuation exactly once, for whichever racer gets there first.
private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock(label: "withTimeout")
    private var continuation: CheckedContinuation<T, Error>?
    private var timer: Task<Void, Never>?

    func arm(_ continuation: CheckedContinuation<T, Error>) {
        lock.perform { self.continuation = continuation }
    }

    func setTimer(_ timer: Task<Void, Never>) {
        let alreadyFinished: Bool = lock.perform {
            guard continuation != nil else { return true }
            self.timer = timer
            return false
        }
        if alreadyFinished {
            timer.cancel()
        }
    }

    func finish(_ result: Result<T, Error>) {
        let (continuation, timer) = lock.perform {
            defer {
                self.continuation = nil
                self.timer = nil
            }
            return (self.continuation, self.timer)
        }
        timer?.cancel()
        continuation?.resume(with: result)
    }
}
