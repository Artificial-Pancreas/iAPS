import SwiftUI

struct DecimalTextField: UIViewRepresentable {
    private var placeholder: String
    @Binding var value: Decimal
    private var formatter: NumberFormatter

    init(
        _ placeholder: String,
        value: Binding<Decimal>,
        formatter: NumberFormatter
    ) {
        self.placeholder = placeholder
        _value = value
        self.formatter = formatter
    }

    func makeUIView(context: Context) -> UITextField {
        let textfield = UITextField()
        textfield.keyboardType = .decimalPad
        textfield.delegate = context.coordinator
        textfield.placeholder = placeholder
        textfield.text = formatter.string(for: value) ?? placeholder
        textfield.textAlignment = .right

        let toolBar = UIToolbar(frame: CGRect(
            x: 0,
            y: 0,
            width: textfield.frame.size.width,
            height: 44
        ))
        let clearButton = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(textfield.clearButtonTapped(button:))
        )
        let doneButton = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(textfield.doneButtonTapped(button:))
        )
        let space = UIBarButtonItem(
            barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace,
            target: nil,
            action: nil
        )
        toolBar.setItems([clearButton, space, doneButton], animated: true)
        textfield.inputAccessoryView = toolBar
        return textfield
    }

    func updateUIView(_: UITextField, context _: Context) {
        // Do nothing, needed for protocol
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalTextField

        init(_ textField: DecimalTextField) {
            parent = textField
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Allow only numbers and decimal characters
            let isNumber = CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string))
            let withDecimal = (
                string == NumberFormatter().decimalSeparator &&
                    textField.text?.contains(string) == false
            )

            if isNumber || withDecimal,
               let currentValue = textField.text as NSString?
            {
                // Update Value
                let proposedValue = currentValue.replacingCharacters(in: range, with: string) as String

                let decimalFormatter = NumberFormatter()
                decimalFormatter.locale = Locale.current
                decimalFormatter.numberStyle = .decimal

                // Try currency formatter then Decimal formatrer
                let number = parent.formatter.number(from: proposedValue) ?? decimalFormatter.number(from: proposedValue) ?? 0.0

                // Set Value
                let double = number.doubleValue
                parent.value = Decimal(double)
            }

            return isNumber || withDecimal
        }

        func textFieldDidEndEditing(
            _ textField: UITextField,
            reason _: UITextField.DidEndEditingReason
        ) {
            // Format value with formatter at End Editing
            textField.text = parent.formatter.string(for: parent.value)
        }
    }
}

// MARK: extension for done button

extension UITextField {
    @objc func doneButtonTapped(button _: UIBarButtonItem) {
        resignFirstResponder()
    }

    @objc func clearButtonTapped(button _: UIBarButtonItem) {
        text = ""
    }
}

// MARK: extension for keyboard to dismiss

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
