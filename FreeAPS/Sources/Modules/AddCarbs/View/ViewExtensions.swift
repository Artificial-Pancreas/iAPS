import Combine
import Foundation
import SwiftUI

extension View {
    /// Moves the cursor to the end of a UITextField when it gains focus.
    func cursorAtEndOnFocus() -> some View {
        onReceive(
            Foundation.NotificationCenter.default
                .publisher(for: UITextField.textDidBeginEditingNotification)
        ) { notification in
            guard let textField = notification.object as? UITextField else { return }
            DispatchQueue.main.async {
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: end, to: end)
            }
        }
    }

    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    // Helper for conditional view modifiers
    @ViewBuilder func when<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension FoodItemDetailed {
    func preferredInfoSheetHeight() -> CGFloat {
        var base: CGFloat = 480
        if let notes = assessmentNotes, !notes.isEmpty { base += 40 }
        if let prep = preparationMethod, !prep.isEmpty { base += 30 }
        if let cues = visualCues, !cues.isEmpty { base += 30 }
        if (standardServing != nil && !standardServing!.isEmpty) || standardServingSize != nil { base += 40 }
        return min(max(base, 460), 680)
    }
}
