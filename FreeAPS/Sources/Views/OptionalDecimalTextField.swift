import SwiftUI
import UIKit

public struct OptionalDecimalTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var value: Decimal?
    var textColor: UIColor
    var textAlignment: NSTextAlignment
    var keyboardType: UIKeyboardType
    var autocapitalizationType: UITextAutocapitalizationType
    var autocorrectionType: UITextAutocorrectionType
    var maxLength: Int?
    var textFieldDidBeginEditing: (() -> Void)?
    var formatter: NumberFormatter
    var autofocus: Bool
    var cleanInput: Bool
    var allowDecimalSeparator: Bool
    var liveEditing: Bool // when true: update the value as the user types; when false: only update the value when the user finishes typing (closes the keyboard)

    public init(
        _ placeholder: String,
        value: Binding<Decimal?>,
        textColor: UIColor = .label,
        textAlignment: NSTextAlignment = .right,
        keyboardType: UIKeyboardType = .decimalPad,
        autocapitalizationType: UITextAutocapitalizationType = .none,
        autocorrectionType: UITextAutocorrectionType = .no,
        maxLength: Int? = nil,
        textFieldDidBeginEditing: (() -> Void)? = nil,
        formatter: NumberFormatter,
        autofocus: Bool = false,
        cleanInput: Bool = true,
        allowDecimalSeparator: Bool = true,
        liveEditing: Bool = false
    ) {
        self.placeholder = placeholder
        _value = value
        self.autofocus = autofocus
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.keyboardType = keyboardType
        self.autocapitalizationType = autocapitalizationType
        self.autocorrectionType = autocorrectionType
        self.maxLength = maxLength
        self.cleanInput = cleanInput
        self.textFieldDidBeginEditing = textFieldDidBeginEditing
        self.formatter = formatter
        formatter.numberStyle = .decimal
        self.allowDecimalSeparator = allowDecimalSeparator
        self.liveEditing = liveEditing
    }

    private func valueAsText() -> String {
        guard let value = value else { return "" }
        /// show no value initially, i.e. empty String
        return value == 0 ? "" : (formatter.string(for: value) ?? "")
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
        textField.text = valueAsText()
        textField.placeholder = placeholder
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
        let cancelButton = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.cancelEdit)
        )

        toolbar
            .items = liveEditing ? [clearButton, flexibleSpace, doneButton] :
            [clearButton, flexibleSpace, cancelButton, doneButton]

        toolbar.sizeToFit()

        return toolbar
    }

    public func updateUIView(_ textField: UITextField, context: Context) {
        if !context.coordinator.isEditing ||
            (context.coordinator.previousSeenValue == nil && value != nil) ||
            (context.coordinator.previousSeenValue != nil && value == nil) ||
            (
                (context.coordinator.previousSeenValue != nil && value != nil) &&
                    abs(context.coordinator.previousSeenValue! - value!) > 0.0000001
            )
        {
            context.coordinator.previousSeenValue = value
            let newText = valueAsText()
            if textField.text != newText {
                textField.text = newText
            }
        }
        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType

        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

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

    fileprivate static let allowedCharacters = CharacterSet(charactersIn: "0123456789,.")

    public final class Coordinator: NSObject {
        var parent: OptionalDecimalTextField
        var textField: UITextField?
        let maxLength: Int?
        var didBecomeFirstResponder = false
        let decimalFormatter: NumberFormatter
        var isEditing: Bool = false
        var previousSeenValue: Decimal?

        var cachedToolbar: UIToolbar?

        init(_ parent: OptionalDecimalTextField, maxLength: Int?) {
            self.parent = parent
            self.maxLength = maxLength
            decimalFormatter = NumberFormatter()
            decimalFormatter.locale = Locale.current
            decimalFormatter.numberStyle = .decimal
        }

        @objc fileprivate func clearText() {
            guard let textField = textField else { return }
            let fullRange = NSRange(location: 0, length: textField.text?.count ?? 0)
            _ = self.textField(textField, shouldChangeCharactersIn: fullRange, replacementString: "")
        }

        @objc func cancelEdit() {
            textField?.text = parent.valueAsText()
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

            if proposedText.trimmingCharacters(in: .whitespaces).isEmpty {
                parent.value = nil
            } else if let number = parent.formatter.number(from: proposedText) {
                let decimalNumber = number.decimalValue
                parent.value = decimalNumber
                textField.text = parent.formatter.string(for: decimalNumber) ?? ""
            } else {
                // invalid input - reset to the original value
                textField.text = parent.valueAsText()
            }
            isEditing = false
        }

        private func handleUpdatedInput() {
            guard parent.liveEditing else { return }
            guard let textField = self.textField else { return }

            let proposedText = textField.text ?? ""
            if proposedText.trimmingCharacters(in: .whitespaces).isEmpty {
                parent.value = nil
                previousSeenValue = nil
            } else if let number = parent.formatter.number(from: proposedText) {
                let decimalNumber = number.decimalValue
                parent.value = decimalNumber
                previousSeenValue = decimalNumber
            } else {
                // invalid input, set value to 0
                parent.value = 0
            }
        }
    }
}

extension OptionalDecimalTextField.Coordinator: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        // Check if the input is a number or the decimal separator
        let isAllowed = OptionalDecimalTextField.allowedCharacters.isSuperset(of: CharacterSet(charactersIn: string))
        if !isAllowed { return false }

        if let text = textField.text {
            let newText = (text as NSString).replacingCharacters(in: range, with: string)

            let decimalSeparatorCount = newText.filter({ $0 == (parent.formatter.decimalSeparator.first ?? ".") }).count
            if decimalSeparatorCount > 1 {
                return false
            }

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
