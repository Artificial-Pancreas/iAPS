import Foundation
import SwiftUI

struct OptionSelectionView: View {
    let title: String
    let options: [(code: String, name: String)]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredOptions: [(code: String, name: String)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.code.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            ForEach(filteredOptions, id: \.code) { item in
                Button {
                    selection = item.code
                    dismiss()
                } label: {
                    HStack {
                        Text(NSLocalizedString(item.name, comment: ""))
                            .foregroundColor(.primary)
                        Spacer()
                        if selection == item.code {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString(title, comment: ""))
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
    }
}
