import Foundation

// actor Broadcast<Element: Sendable> {
//    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
//
//    func subscribe() -> AsyncStream<Element> {
//        let id = UUID()
//        let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
//        continuations[id] = continuation
//        continuation.onTermination = { [weak self] _ in
//            Task { await self?.unsubscribe(id) }
//        }
//        return stream
//    }
//
//    func send(_ value: Element) {
//        continuations.values.forEach { $0.yield(value) }
//    }
//
//    private func unsubscribe(_ id: UUID) {
//        continuations.removeValue(forKey: id)
//    }
// }
