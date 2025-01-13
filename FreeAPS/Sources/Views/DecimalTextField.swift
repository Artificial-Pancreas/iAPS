import SwiftUI
import UIKit

public struct DecimalTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var value: Decimal
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

    public init(
        _ placeholder: String,
        value: Binding<Decimal>,
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
        allowDecimalSeparator: Bool = true
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
    }

    public func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        context.coordinator.textField = textField
        textField.inputAccessoryView = cleanInput ? makeDoneToolbar(for: textField, context: context) : nil
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin), for: .editingDidBegin)
        textField.delegate = context.coordinator
        if value == 0 { /// show no value initially, i.e. empty String
            textField.text = ""
        } else {
            textField.text = formatter.string(for: value)
        }
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

        toolbar.items = [clearButton, flexibleSpace, doneButton]
        toolbar.sizeToFit()
        return toolbar
    }

    public func updateUIView(_ textField: UITextField, context: Context) {
        if value != 0 {
            let newText = formatter.string(for: value) ?? ""
            if textField.text != newText {
                textField.text = newText
            }
        }

        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType

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
        var parent: DecimalTextField
        var textField: UITextField?
        let maxLength: Int?
        var didBecomeFirstResponder = false
        let decimalFormatter: NumberFormatter

        init(_ parent: DecimalTextField, maxLength: Int?) {
            self.parent = parent
            self.maxLength = maxLength
            decimalFormatter = NumberFormatter()
            decimalFormatter.locale = Locale.current
            decimalFormatter.numberStyle = .decimal
        }

        @objc fileprivate func clearText() {
            parent.value = 0
            textField?.text = ""
        }

        @objc fileprivate func editingDidBegin(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.moveCursorToEnd()
            }
        }
    }
}

extension DecimalTextField.Coordinator: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        // Check if the input is a number or the decimal separator
        let isNumber = CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string))
        let isDecimalSeparator = (string == decimalFormatter.decimalSeparator && textField.text?.contains(string) == false)

        // Only proceed if the input is a valid number or decimal separator
        if isNumber || isDecimalSeparator && parent.allowDecimalSeparator,
           let currentText = textField.text as NSString?
        {
            // Get the proposed new text
            let proposedText = currentText.replacingCharacters(in: range, with: string)

            // Try to convert proposed text to number
            let number = parent.formatter.number(from: proposedText) ?? decimalFormatter.number(from: proposedText)

            // Update the binding value if conversion is successful
            if let number = number {
                parent.value = number.decimalValue
            } else {
                parent.value = 0
            }
        }

        // Allow the change if it's a valid number or decimal separator
        return isNumber || isDecimalSeparator && parent.allowDecimalSeparator
    }

    public func textFieldDidBeginEditing(_: UITextField) {
        parent.textFieldDidBeginEditing?()
    }
}

extension UITextField {
    func moveCursorToEnd() {
        dispatchPrecondition(condition: .onQueue(.main))
        let newPosition = endOfDocument
        selectedTextRange = textRange(from: newPosition, to: newPosition)
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
