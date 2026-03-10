import SwiftUI
import UIKit

public struct DismissableTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var textColor: UIColor
    var textAlignment: NSTextAlignment
    var keyboardType: UIKeyboardType
    var autocapitalizationType: UITextAutocapitalizationType
    var autocorrectionType: UITextAutocorrectionType
    var maxLength: Int?
    var textFieldDidBeginEditing: (() -> Void)?
    var autofocus: Bool
    var returnKeyType: UIReturnKeyType
    var cleanInput: Bool
    var liveEditing: Bool // when true: update the text as the user types; when false: only update the text when the user finishes typing (closes the keyboard)
    var onSubmit: (() -> Void)?

    public init(
        _ placeholder: String,
        text: Binding<String>,
        textColor: UIColor = .label,
        textAlignment: NSTextAlignment = .natural,
        keyboardType: UIKeyboardType = .default,
        autocapitalizationType: UITextAutocapitalizationType = .none,
        autocorrectionType: UITextAutocorrectionType = .no,
        maxLength: Int? = nil,
        textFieldDidBeginEditing: (() -> Void)? = nil,
        autofocus: Bool = false,
        returnKeyType: UIReturnKeyType = .default,
        cleanInput: Bool = true,
        liveEditing: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        _text = text
        self.autofocus = autofocus
        self.returnKeyType = returnKeyType
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.keyboardType = keyboardType
        self.autocapitalizationType = autocapitalizationType
        self.autocorrectionType = autocorrectionType
        self.maxLength = maxLength
        self.cleanInput = cleanInput
        self.textFieldDidBeginEditing = textFieldDidBeginEditing
        self.liveEditing = liveEditing
        self.onSubmit = onSubmit
    }

    public func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        context.coordinator.textField = textField

        if cleanInput {
            if context.coordinator.cachedToolbar == nil {
                context.coordinator.cachedToolbar = makeDoneToolbar(for: textField, context: context)
            }
            textField.inputAccessoryView = context.coordinator.cachedToolbar
        }

        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin), for: .editingDidBegin)
        textField.delegate = context.coordinator
        textField.text = text
        textField.placeholder = placeholder

        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        return textField
    }

    private func makeDoneToolbar(for textField: UITextField, context: Context) -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done,
            target: textField,
            action: #selector(UITextField.resignFirstResponder)
        )
        let clearButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.clearText)
        )

        toolbar
            .items = [clearButton, flexibleSpace, doneButton]
        toolbar.sizeToFit()
        return toolbar
    }

    public func updateUIView(_ textField: UITextField, context: Context) {
        if !context.coordinator.isEditing || context.coordinator.previousSeentext != text {
            context.coordinator.previousSeentext = text
            let newText = text
            if textField.text != newText {
                textField.text = newText
            }
        }
        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType
        textField.returnKeyType = returnKeyType

        if autofocus, !context.coordinator.didBecomeFirstResponder {
            if textField.window != nil, textField.becomeFirstResponder() {
                context.coordinator.didBecomeFirstResponder = true
            }
        } else if !autofocus, context.coordinator.didBecomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = false
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self, maxLength: maxLength)
    }

    public final class Coordinator: NSObject {
        var parent: DismissableTextField
        var textField: UITextField?
        let maxLength: Int?
        var didBecomeFirstResponder = false
        var isEditing: Bool = false
        var previousSeentext: String = ""

        var cachedToolbar: UIToolbar?

        init(_ parent: DismissableTextField, maxLength: Int?) {
            self.parent = parent
            self.maxLength = maxLength
        }

        @objc fileprivate func clearText() {
            guard let textField = textField else { return }
            let fullRange = NSRange(location: 0, length: textField.text?.count ?? 0)
            _ = self.textField(textField, shouldChangeCharactersIn: fullRange, replacementString: "")
        }

        @objc func cancelEdit() {
            textField?.text = parent.text
            textField?.resignFirstResponder()
        }

        @objc fileprivate func editingDidBegin(_ textField: UITextField) {
            isEditing = true
            DispatchQueue.main.async {
                textField.moveCursorToEnd()
            }
        }

        @objc public func textFieldDidEndEditing(_: UITextField) {
            guard let textField = self.textField else { return }

            let proposedText = textField.text ?? ""

            parent.text = proposedText
            isEditing = false
        }

        private func handleUpdatedInput() {
            guard parent.liveEditing else { return }
            guard let textField = self.textField else { return }

            let proposedText = textField.text ?? ""

            parent.text = proposedText
            previousSeentext = proposedText
        }

        public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit?()
            textField.resignFirstResponder()
            return true
        }
    }
}

extension DismissableTextField.Coordinator: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        if let text = textField.text {
            let newText = (text as NSString).replacingCharacters(in: range, with: string)

            textField.text = newText
            handleUpdatedInput()
            return false
        }
        return true
    }

    public func textFieldDidBeginEditing(_: UITextField) {
        parent.textFieldDidBeginEditing?()
    }
}
