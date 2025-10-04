import LoopKitUI
import SwiftUI
import Swinject

extension CalendarShare {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                Form {
                    Section {
                        Toggle("Create Events in Calendar", isOn: $state.createCalendarEvents)
                        if state.calendarIDs.isNotEmpty {
                            Picker("Calendar", selection: $state.currentCalendarID) {
                                ForEach(state.calendarIDs, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            Toggle("Display Emojis as Labels", isOn: $state.displayCalendarEmojis)
                            Toggle("Display IOB and COB", isOn: $state.displayCalendarIOBandCOB)
                        } else if state.createCalendarEvents {
                            Text(
                                "If you are not seeing calendars to choose here, please go to Settings -> iAPS -> Calendars and change permissions to \"Full Access\""
                            ).font(.footnote)

                            Button("Open Settings") {
                                // Get the settings URL and open it
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
