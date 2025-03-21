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
                    Toggle("Share and Backup all of your Settings and Statistics", isOn: $state.uploadStats)
                    if state.uploadStats {
                        Picker("Sex", selection: $state.sex) {
                            ForEach(Sex.allCases) { sex in
                                Text(NSLocalizedString(sex.rawValue, comment: "")).tag(Optional(sex.rawValue))
                            }
                        }.onChange(of: state.sex) {
                            state.saveSetting()
                        }
                        HStack {
                            DatePicker("Birth Date", selection: $state.birthDate, in: dateRange, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                        }
                    }
                } header: { Text("Upload Settings and Statistics") }
                footer: {
                    Text(
                        "\nIf you enable \"Share and Backup\" daily backups of your settings and statistics will be made to online database.\n\nMake sure to copy and save your recovery token below. The recovery token is required to import your settings to another phone when using the onboarding view."
                    )
                }

                Section {}
                footer: {
                    Text(
                        "Every bit of information you choose to share is uploaded anonymously. To prevent duplicate uploads, the data is identified with a unique random string saved on your phone, the recovery token."
                    )
                }

                Section {
                    HStack {
                        Text(display ? state.identfier : NSLocalizedString("Tap to display", comment: "Token display button"))
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
                header: { Text("Your recovery token") }

                footer: {
                    Text((copied && display) ? "" : display ? "Long press to copy" : "")
                        .foregroundStyle((display && !copied) ? .blue : .secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Section {}
                footer: {
                    let statisticsLink = URL(string: "https://open-iaps.app/user/" + state.identfier)!

                    Button("View Personal Statistics") {
                        UIApplication.shared.open(statisticsLink, options: [:], completionHandler: nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.system(size: 15))
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear {
                configureView()
                state.savedSettings()
            }
            .navigationBarTitle("Share and Backup")
        }
    }
}
