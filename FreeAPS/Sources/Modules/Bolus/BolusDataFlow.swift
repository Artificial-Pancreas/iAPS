import Foundation

enum Bolus {
    enum Config {}

    /// A meal entered in Add Meal and not stored yet. Bolus stores it, on enact or save, and is its only writer
    struct MealDraft: Identifiable, Hashable, Sendable {
        // navigation identity: CarbsEntry's == and hash use createdAt only
        let id = UUID()
        let entry: CarbsEntry
        /// Add Meal fires it when Bolus is popped (back). Bolus can't tell that from its own disappear,
        /// which can also come with a back swipe that is then cancelled
        let popped: PopSignal

        @MainActor init(entry: CarbsEntry) {
            self.entry = entry
            popped = PopSignal()
        }

        static func == (lhs: MealDraft, rhs: MealDraft) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    @MainActor final class PopSignal {
        private var actions: [() -> Void] = []

        func onFire(_ action: @escaping () -> Void) {
            actions.append(action)
        }

        /// Once: the actions are dropped
        func fire() {
            let actions = self.actions
            self.actions = []
            actions.forEach { $0() }
        }
    }
}

protocol BolusProvider: Provider {}
