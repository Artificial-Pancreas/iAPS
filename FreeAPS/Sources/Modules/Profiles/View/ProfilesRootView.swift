import Combine
import CoreData
import SwiftUI
import Swinject

extension Profiles {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Profiles.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var profiles: FetchedResults<Profiles>

        @FetchRequest(
            entity: ActiveProfile.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(
                format: "active == true"
            )
        ) var currentProfile: FetchedResults<ActiveProfile>

        @State var onboardingView = false
        @State var selectedProfile = ""
        @State var int = 2
        @State var inSitu = true
        @State var id = ""

        var body: some View {
            Form {
                let uploaded = profiles.filter({ $0.uploaded == true })
                Section {
                    HStack {
                        Text("Current profile:").foregroundStyle(.secondary)
                        Spacer()
                        if let p = currentProfile.first, let name = p.name {
                            Text(name)
                            if profiles.first(where: { $0.name == name && $0.uploaded }) != nil {
                                Image(systemName: "cloud")
                            }
                        } else { Text("default") }
                    }
                } header: {
                    Text("Active settings")
                }

                Section {
                    TextField("Name", text: $state.name)

                    Button("Save") {
                        state.save(state.name)
                        state.activeProfile(state.name)
                    }.disabled(state.name.isEmpty)

                } header: {
                    Text("Save as new profile")
                }

                Section {
                    Section {
                        if !state.backup { Text("Backup Disabled") }
                        else if profiles.isEmpty { Text("No profiles saved")
                        } else if profiles.first == uploaded.last, profiles.count == 1 {
                            Text("No other profiles saved")
                        } else {
                            ForEach(uploaded) { profile in
                                profilesView(for: profile)
                            }.onDelete(perform: removeProfile)
                        }
                    }
                } header: {
                    HStack {
                        Text("Load Profile")
                        Image(systemName: "cloud").textCase(nil).foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                }

                Section {}
                footer: {
                    HStack {
                        Text(
                            "Your active profile is updated and uploaded automatically whenever settings are changed and on a daily basis, provided backup is enabled in Sharing settings."
                        )
                    }
                }.textCase(nil)
                    .font(.previewNormal)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $onboardingView) {
                ProfilePicker.RootView(resolver: resolver, int: $int, profile: $selectedProfile, inSitu: $inSitu, id_: $id)
            }
        }

        @ViewBuilder private func profilesView(for preset: Profiles) -> some View {
            if (preset.name ?? "") == (currentProfile.first?.name ?? "BlaBlaXX") {
                Text(preset.name ?? "").foregroundStyle(.secondary)
            } else {
                Text(preset.name ?? "")
                    .foregroundStyle(.blue)
                    .padding(.trailing, 40)
                    .onTapGesture {
                        selectedProfile = preset.name ?? ""
                        id = state.getIdentifier()
                        onboardingView.toggle()
                        // state.activeProfile(selectedProfile)
                    }
            }
        }

        private func removeProfile(at offsets: IndexSet) {
            for index in offsets {
                let profile = profiles[index]
                moc.delete(profile)
            }
            do {
                try moc.save()
            } catch {
                // To do: add error
            }
        }
    }
}
