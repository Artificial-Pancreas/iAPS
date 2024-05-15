import SwiftUI
import Swinject

public enum Sex: String, CaseIterable, Identifiable {
    case woman = "Woman"
    case man = "Man"
    case other = "Other"
    case secret = "Secret"
    public var id: Self { self }
}

extension Sharing {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var display: Bool = false
        @State private var copied: Bool = false

        let dateRange: ClosedRange<Date> = {
            let calendar = Calendar.current
            let year = Date.now.year
            let month = Date.now.month

            let startComponents = DateComponents(year: 1920, month: 1)
            let endComponents = DateComponents(year: year, month: month)
            return calendar.date(from: startComponents)!
                ...
                calendar.date(from: endComponents)!
        }()

        var body: some View {
            Form {
                Section {
                    Toggle("Share all of your Statistics", isOn: $state.uploadStats)
                    if state.uploadStats {
                        Picker("Sex", selection: $state.sex) {
                            ForEach(Sex.allCases) { sex in
                                Text(NSLocalizedString(sex.rawValue, comment: "")).tag(Optional(sex.rawValue))
                            }
                        }.onChange(of: state.sex) { _ in
                            state.saveSetting()
                        }
                        HStack {
                            DatePicker("Birth Date", selection: $state.birtDate, in: dateRange, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                        }
                    }
                } header: { Text("Statistics") }

                if !state.uploadStats {
                    Section {
                        Toggle("Just iAPS version number", isOn: $state.uploadVersion)
                    } header: { Text("Share Bare Minimum") }
                }

                Section {}
                footer: {
                    Text(
                        "Every bit of information you choose to share is uploaded anonymously. To prevent duplicate uploads, the data is identified with a unique random string saved on your phone."
                    )
                }

                Section {
                    HStack {
                        Text(display ? state.identfier : "Tap to display")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onTapGesture { display.toggle() }
                    .onLongPressGesture {
                        if display {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            UIPasteboard.general.string = state.identfier
                            copied = true
                        }
                    }
                }
                header: { Text("Your identifier") }
                footer: { Text((copied && display) ? "Copied" : "") }

                Section {}
                footer: {
                    Text("https://open-iaps.app/statistics")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear {
                configureView()
                state.savedSettings()
            }
            .navigationBarTitle("Share your data anonymously")
        }
    }
}
