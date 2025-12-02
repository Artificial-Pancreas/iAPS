import SwiftUI

struct MultiplierEditorView: View {
    @Binding var grams: Double
    @Environment(\.dismiss) var dismiss
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("Amount")
                        .font(.headline)
                        .fontWeight(.bold)

                    Spacer()

                    Button("Exit") {
                        saveAndDismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))

                // Hauptinhalt
                VStack(spacing: 20) {
                    // Eingabefeld
                    VStack(spacing: 8) {
                        Text("Enter desired quantity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("0", text: $inputText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(PlainTextFieldStyle())
                                .focused($isInputFocused)
                                .font(.system(size: 40, weight: .bold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 150)

                            Text("g")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 20)

                    // Schnellauswahl
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach([50, 100, 150, 200, 250, 300, 400, 500], id: \.self) { value in
                            Button {
                                inputText = "\(value)"
                            } label: {
                                Text("\(value)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 70, height: 50)
                                    .background(grams == Double(value) ? Color.blue : Color.gray.opacity(0.1))
                                    .foregroundColor(grams == Double(value) ? .white : .primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Übernehmen-Button
                    Button(action: {
                        saveAndDismiss()
                    }) {
                        Text("Accept quantity")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
                }
            }
            .onAppear {
                inputText = String(format: "%.0f", grams)
                isInputFocused = true
            }
        }
    }

    private func saveAndDismiss() {
        if let value = Double(inputText.replacingOccurrences(of: ",", with: ".")) {
            grams = value
        }
        dismiss()
    }
}
