import Contacts
import ContactsUI
import SwiftUI
import Swinject

extension ContactTrick {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var contactStore = CNContactStore()
        @State private var authorization = CNContactStore.authorizationStatus(for: .contacts)

        var body: some View {
            Form {
                switch authorization {
                case .authorized:
                    Section(header: Text("Contacts")) {
                        list
                        addButton
                    }
                    Section {
                        HStack {
                            if state.syncInProgress {
                                ProgressView().padding(.trailing, 10)
                            }
                            Button { state.save() }
                            label: {
                                Text(state.syncInProgress ? "Saving..." : "Save")
                            }
                            .disabled(state.syncInProgress || state.items.isEmpty)
                        }
                    }

                case .notDetermined:
                    Section {
                        Text(
                            "Need to ask for contacts access"
                        )
                    }
                    Section {
                        Button(action: onRequestContactsAccess) {
                            Text("Grant access to contacts")
                        }
                    }

                case .denied:
                    Section {
                        Text(
                            "Contacts access denied"
                        )
                    }

                case .restricted:
                    Section {
                        Text(
                            "Contacts access - restricted (parental control?)"
                        )
                    }

                @unknown default:
                    Section {
                        Text(
                            "Contacts access - unknown"
                        )
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Contact Trick")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                trailing: EditButton()
            )
        }

        private func contactSettings(for index: Int) -> some View {
            EntryView(entry: $state.items[index].entry)
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, _ in
                    NavigationLink(destination: contactSettings(for: index)) {
                        HStack {
                            Text(
                                state.items[index].entry.displayName ?? "Contact not selected"
                            )
                            .font(.body)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                            Spacer()

                            Text(
                                state.items[index].entry.primary.displayName
                            )
                            .foregroundColor(.accentColor)
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private var addButton: some View {
            AnyView(Button(action: onAdd) { Text("Add") })
        }

        func onAdd() {
            state.add()
        }

        func onRequestContactsAccess() {
            contactStore.requestAccess(for: .contacts) { _, _ in
                DispatchQueue.main.async {
                    authorization = CNContactStore.authorizationStatus(for: .contacts)
                }
            }
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
        }
    }

    struct EntryView: View {
        @Binding var entry: ContactTrickEntry
        @State private var showContactPicker = false
        @State private var availableFonts: [String]? = nil

        private let fontSizes: [Int] = [70, 80, 90, 100, 110, 120, 130, 140, 150]
        private let ringWidths: [Int] = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
        private let ringGaps: [Int] = [0, 1, 2, 3, 4, 5]

        var body: some View {
            Form {
                Section {
                    if let displayName = entry.displayName {
                        Text(displayName)
                    }
                    Button(entry.contactId == nil ? "Select contact" : "Change contact") {
                        showContactPicker = true
                    }
                }
                Section {
                    Toggle("Enabled", isOn: $entry.enabled)
                    Picker(
                        selection: $entry.layout,
                        label: Text("Layout")
                    ) {
                        ForEach(ContactTrickLayout.allCases) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                }
                Section {
                    switch entry.layout {
                    case .single:
                        Picker(
                            selection: $entry.primary,
                            label: Text("Primary")
                        ) {
                            ForEach(ContactTrickValue.allCases) { v in
                                Text(v.displayName).tag(v)
                            }
                        }
                        Picker(
                            selection: $entry.top,
                            label: Text("Top")
                        ) {
                            ForEach(ContactTrickValue.allCases) { v in
                                Text(v.displayName).tag(v)
                            }
                        }
                        Picker(
                            selection: $entry.bottom,
                            label: Text("Bottom")
                        ) {
                            ForEach(ContactTrickValue.allCases) { v in
                                Text(v.displayName).tag(v)
                            }
                        }
                    case .split:
                        Picker(
                            selection: $entry.top,
                            label: Text("Top")
                        ) {
                            ForEach(ContactTrickValue.allCases) { v in
                                Text(v.displayName).tag(v)
                            }
                        }
                        Picker(
                            selection: $entry.bottom,
                            label: Text("Bottom")
                        ) {
                            ForEach(ContactTrickValue.allCases) { v in
                                Text(v.displayName).tag(v)
                            }
                        }
                    }
                }

                Section(header: Text("Ring")) {
                    Picker(
                        selection: $entry.ring1,
                        label: Text("Outer")
                    ) {
                        ForEach(ContactTrickLargeRing.allCases) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    Picker(
                        selection: $entry.ringWidth,
                        label: Text("Width")
                    ) {
                        ForEach(ringWidths, id: \.self) { s in
                            Text("\(s)").tag(s)
                        }
                    }
                    Picker(
                        selection: $entry.ringGap,
                        label: Text("Gap")
                    ) {
                        ForEach(ringGaps, id: \.self) { s in
                            Text("\(s)").tag(s)
                        }
                    }
                }

                Section(header: Text("Font")) {
                    if availableFonts == nil {
                        HStack {
                            Spacer()
                            Button {
                                loadFonts()
                            } label: {
                                Text(entry.fontName)
                            }
                        }
                    } else {
                        Picker(
                            selection: $entry.fontName,
                            label: EmptyView()
                        ) {
                            ForEach(availableFonts!, id: \.self) { f in
                                Text(f).tag(f)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .labelsHidden()
                    }
                    Picker(
                        selection: $entry.fontSize,
                        label: Text("Size")
                    ) {
                        ForEach(fontSizes, id: \.self) { s in
                            Text("\(s)").tag(s)
                        }
                    }
                    Picker(
                        selection: $entry.fontTracking,
                        label: Text("Tracking")
                    ) {
                        ForEach(FontTracking.allCases) { w in
                            Text(w.displayName).tag(w)
                        }
                    }
                    if entry.isDefaultFont() {
                        Picker(
                            selection: $entry.fontWeight,
                            label: Text("Weight")
                        ) {
                            ForEach(FontWeight.allCases) { w in
                                Text(w.displayName).tag(w)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Dark mode", isOn: $entry.darkMode)
                }
            }
//            .navigationTitle(entry.displayName ?? "Contact not selected")
            .fullScreenCover(isPresented: $showContactPicker) {
                ContactPicker(entry: $entry)
            }
        }

        private func loadFonts() {
            if availableFonts != nil {
                return
            }
            var data = [String]()

            data.append("Default Font")
            UIFont.familyNames.forEach { family in
                UIFont.fontNames(forFamilyName: family).forEach { font in
                    data.append(font)
                }
            }
            availableFonts = data
        }
    }

    struct ContactPicker: UIViewControllerRepresentable {
        @Binding var entry: ContactTrickEntry

        func makeUIViewController(context: Context) -> CNContactPickerViewController {
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: CNContactPickerViewController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, CNContactPickerDelegate {
            var parent: ContactPicker

            init(_ parent: ContactPicker) {
                self.parent = parent
            }

            func contactPicker(_: CNContactPickerViewController, didSelect contact: CNContact) {
                parent.entry.contactId = contact.identifier
                let display = if let emailAddress = contact.emailAddresses.first {
                    "\(emailAddress.value)"
                } else {
                    "\(contact.familyName) \(contact.givenName))"
                }
                if display.isEmpty {
                    parent.entry.displayName = "Unnamed contact"
                } else {
                    parent.entry.displayName = display
                }
            }
        }
    }
}
