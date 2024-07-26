import Combine
import CoreData
import SwiftUI
import Swinject

extension ProfilePicker {
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

        @State var selectedProfile = ""
        @State var id = ""
        @State var lifetime = Lifetime()

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Current profile:").foregroundStyle(.secondary)
                        Spacer()
                        if let p = currentProfile.first {
                            Text(p.name ?? "default")

                            if let exists = profiles.first(where: { $0.name == (p.name ?? "default") }), exists.uploaded {
                                Image(systemName: "cloud")
                            }
                        } else {
                            Text("default")
                            if profiles.first?.uploaded ?? false {
                                Image(systemName: "cloud")
                            }
                        }
                    }
                } header: { Text("Active settings") }

                footer: {
                    Text(
                        "Updates and uploads to the cloud automatically whenever settings are changed and on a daily basis, provided backup is enabled."
                    )
                }

                Section {
                    TextField("Name", text: $state.name)

                    Button("Save") {
                        state.save(state.name)
                        state.activeProfile(state.name)
                        upload()
                    }.disabled(state.name.isEmpty)

                } header: {
                    Text("Save as new profile")
                }

                Section {
                    let uploaded = profiles.filter({ $0.uploaded == true })
                    Section {
                        if profiles.isEmpty { Text("No profiles saved")
                        } else if profiles.first == uploaded.last, profiles.count == 1 {
                            Text("No other profiles saved")
                        } else {
                            ForEach(uploaded) { profile in
                                profilesView(for: profile)
                                    .deleteDisabled(profile.name == "default" || profile.name == currentProfile.first?.name ?? "")
                            }
                            .onDelete(perform: removeProfile)
                        }
                    }
                } header: {
                    HStack {
                        Text("Load Profile from")
                        Image(systemName: "cloud").textCase(nil).foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                }

                Section {
                    Button("Upload now") {
                        // If no profiles saved yet
                        if (profiles.first?.name ?? "NoneXXX") == "NoneXXX" || (profiles.first?.name ?? "default" == "default") {
                            state.save("default")
                            state.activeProfile("default")
                        }
                        upload()
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(state.backup ? Color(.systemBlue) : Color(.systemGray4))
                    .tint(.white)

                } header: { Text("Backup now") }

                footer: {
                    if !state.backup {
                        Text("\nBackup disabled in Sharing settings").foregroundStyle(.orange).bold().textCase(nil)
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear { configureView() }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
        }

        @ViewBuilder private func profilesView(for preset: Profiles) -> some View {
            if (preset.name ?? "") == (currentProfile.first?.name ?? "BlaBlaXX") {
                Text(preset.name ?? "").foregroundStyle(.secondary)
            } else {
                Text(preset.name ?? "")
                    .foregroundStyle(.blue)
                    .navigationLink(to: .restore(
                        int: 2,
                        profile: preset.name ?? "",
                        inSitu: true,
                        id_: state.getIdentifier(),
                        uniqueID: state.getIdentifier()
                    ), from: self)
                    .onTapGesture {
                        selectedProfile = preset.name ?? ""
                    }
            }
        }

        private func removeProfile(at offsets: IndexSet) {
            let database = Database(token: state.getIdentifier())
            for index in offsets {
                let profile = profiles[index]

                database.deleteProfile(profile.name ?? "")
                    .sink { completion in
                        switch completion {
                        case .finished:
                            debug(.service, "Profiles \(profile.name ?? "") deleted from database")
                            self.moc.delete(profile)
                            do { try moc.save() } catch { /* To do: add error */ }
                        case let .failure(error):
                            debug(
                                .service,
                                "Failed deleting \(profile.name ?? "") from database. " + error.localizedDescription
                            )
                        }
                    }
                receiveValue: {}
                    .store(in: &lifetime)
            }
        }

        private func upload() {
            let b = BaseNightscoutManager(resolver: resolver)
            b.uploadProfileAndSettings(true)
        }
    }
}
