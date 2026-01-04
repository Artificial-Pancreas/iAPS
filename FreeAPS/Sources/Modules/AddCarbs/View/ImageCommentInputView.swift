import SwiftUI

struct ImageCommentInputView: View {
    let image: UIImage
    let onContinue: (String?) -> Void
    let onCancel: () -> Void

    @State private var comment: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Image preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Comment text field
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )

                    TextEditor(text: $comment)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .focused($isTextFieldFocused)

                    // Placeholder
                    if comment.isEmpty {
                        Text("Additional details for AI...")
                            .font(.body)
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 100)
                .onSubmit {
                    handleContinue()
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip" : "Continue") {
                        handleContinue()
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isTextFieldFocused = true
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func handleContinue() {
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        onContinue(trimmedComment.isEmpty ? nil : trimmedComment)
    }
}
