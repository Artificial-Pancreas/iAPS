import Foundation
import SwiftUI

struct ModelQueryEditor: View {
    struct Example: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    let title: String
    let loadText: () -> String
    let saveText: (String) -> Void
    let examples: [Example]

    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var originalText: String = ""
    @State private var hasLoaded: Bool = false

    init(
        title: String,
        loadText: @escaping () -> String,
        saveText: @escaping (String) -> Void,
        examples: [String: String] = [:]
    ) {
        self.title = title
        self.loadText = loadText
        self.saveText = saveText
        let mappedExamples = examples.map { key, value in Example(title: key, text: value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        self.examples = mappedExamples
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                if !examples.isEmpty {
                    HStack {
                        Menu {
                            ForEach(examples) { example in
                                Button(example.title) {
                                    text = example.text
                                }
                            }
                        } label: {
                            Label("Examples", systemImage: "text.book.closed")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(.accentColor)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)

                    TextEditor(text: $text)
                        .font(.system(.subheadline, design: .monospaced))
                        .allowsTightening(true)
                        .textInputAutocapitalization(.never)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            if !hasLoaded {
                let loaded = loadText()
                self.originalText = loaded
                self.text = loaded
                self.hasLoaded = true
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveText(text)
                    dismiss()
                }
                .disabled(text == originalText)
            }
        }
    }
}
