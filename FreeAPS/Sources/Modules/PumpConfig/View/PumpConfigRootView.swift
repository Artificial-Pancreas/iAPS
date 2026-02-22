import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        private func ageString(_ date: Date?) -> String {
            guard let date = date else { return "–" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let rel = formatter.localizedString(for: date, relativeTo: Date())
            let abs = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
            return "\(abs)\n(\(rel))"
        }

        var body: some View {
            NavigationView {
                ZStack {
                    Form {
                        if let pumpManager = state.deviceManager.pumpManager, pumpManager.isOnboarded {
                            Section(header: Text("Modell")) {
                                Button {
                                    state.setupPump(pumpManager.pluginIdentifier)
                                } label: {
                                    HStack {
                                        Image(uiImage: pumpManager.smallImage ?? UIImage())
                                            .resizable()
                                            .scaledToFit()
                                            .padding()
                                            .frame(maxWidth: 100)
                                        Text(pumpManager.localizedTitle)
                                    }
                                }
                            }

                            Section {
                                if let status = pumpManager.pumpStatusHighlight?.localizedMessage {
                                    HStack {
                                        Text(status.replacingOccurrences(of: "\n", with: " "))
                                    }
                                }
                                if state.pumpManagerStatus?.deliveryIsUncertain ?? false {
                                    HStack {
                                        Text("Pump delivery uncertain").foregroundColor(.red)
                                    }
                                }
                                if state.alertNotAck {
                                    Spacer()
                                    Button("Acknowledge all alerts") { state.ack() }
                                }
                            }

                            if pumpManager.pluginIdentifier == "Dana" {
                                Section(header: Text("Nightscout Actions")) {
                                    DatePicker(
                                        "Changed At",
                                        selection: $state.changedAt,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    Button("Log Site Change") {
                                        state.confirmation = .siteChange
                                    }
                                    Button("Log Reservoir Change") {
                                        state.confirmation = .reservoirChange
                                    }
                                }

                                Section(
                                    header: Text("Korrekturen"),
                                    footer: Text(
                                        "If an automatic pump event overwrote your manual time, use these buttons to delete the newest incorrect entry from Nightscout."
                                    )
                                ) {
                                    Button("App intern synchronisieren") { state.confirmation = .forceSync }
                                        .foregroundColor(.orange)

                                    Button("Delete newest Site Change") {
                                        state.confirmation = .deleteSiteChange
                                    }
                                    .foregroundColor(.red)
                                    Button("Delete newest Reservoir Change") {
                                        state.confirmation = .deleteReservoirChange
                                    }
                                    .foregroundColor(.red)
                                }

                                Section(
                                    header: Text("Insulin Age Reconciliation"),
                                    footer: Text(
                                        "Compares Dana pump history, iAPS local storage, and Nightscout. If the discrepancy exceeds 1 hour, you can choose which source to trust."
                                    )
                                ) {
                                    Button {
                                        state.syncInsulinAges()
                                    } label: {
                                        HStack {
                                            if state.isSyncingInsulinAge {
                                                ProgressView().padding(.trailing, 4)
                                            }
                                            Text(state.isSyncingInsulinAge ? "Syncing…" : "Check Insulin Age Sync")
                                        }
                                    }
                                    .disabled(state.isSyncingInsulinAge)
                                }
                            }

                        } else {
                            Section {
                                ForEach(state.deviceManager.availablePumpManagers, id: \.identifier) { pump in
                                    VStack(alignment: .leading) {
                                        Button("Add " + pump.localizedTitle) {
                                            state.setupPump(pump.identifier)
                                        }
                                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Pump config")
                    .navigationBarTitleDisplayMode(.inline)
                    // --- ERSTES SHEET: Hängt am Formular ---
                    .sheet(isPresented: $state.pumpSetupPresented) {
                        if let pumpIdentifier = state.pumpIdentifierToSetUp {
                            if let pumpManager = state.deviceManager.pumpManager, pumpManager.isOnboarded {
                                PumpSettingsView(
                                    pumpManager: pumpManager,
                                    deviceManager: state.deviceManager,
                                    completionDelegate: state
                                )
                            } else {
                                PumpSetupView(
                                    pumpIdentifier: pumpIdentifier,
                                    pumpInitialSettings: state.initialSettings,
                                    deviceManager: state.deviceManager,
                                    completionDelegate: state
                                )
                            }
                        }
                    }
                    .alert(item: $state.confirmation) { confirmationType in
                        // HIER IST DER FEHLENDE FALL HINZUGEFÜGT WORDEN
                        switch confirmationType {
                        case .siteChange:
                            return Alert(
                                title: Text("Log Site Change?"),
                                message: Text("Do you want to log a site change for\n\(state.formattedChangedAt)?"),
                                primaryButton: .default(Text("Log"), action: { state.logSiteChange() }),
                                secondaryButton: .cancel()
                            )
                        case .reservoirChange:
                            return Alert(
                                title: Text("Log Reservoir Change?"),
                                message: Text("Do you want to log a reservoir change for\n\(state.formattedChangedAt)?"),
                                primaryButton: .default(Text("Log"), action: { state.logReservoirChange() }),
                                secondaryButton: .cancel()
                            )
                        case .forceSync:
                            return Alert(
                                title: Text("Intern synchronisieren?"),
                                message: Text(
                                    "Dies korrigiert nur die Anzeige in der App auf \(state.formattedChangedAt). Fortfahren?"
                                ),
                                primaryButton: .destructive(Text("Synchronisieren"), action: { state.forceInternalSync() }),
                                secondaryButton: .cancel()
                            )
                        case .deleteSiteChange:
                            return Alert(
                                title: Text("Delete Site Change?"),
                                message: Text("Are you sure you want to delete the newest site change from Nightscout?"),
                                primaryButton: .destructive(Text("Delete"), action: { state.deleteLatestSiteChange() }),
                                secondaryButton: .cancel()
                            )
                        case .deleteReservoirChange:
                            return Alert(
                                title: Text("Delete Reservoir Change?"),
                                message: Text("Are you sure you want to delete the newest reservoir change from Nightscout?"),
                                primaryButton: .destructive(Text("Delete"), action: { state.deleteLatestReservoirChange() }),
                                secondaryButton: .cancel()
                            )
                        }
                    }

                    if state.showUploadMessage {
                        VStack(spacing: 12) {
                            Image(
                                systemName: state.uploadMessageText.contains("Error")
                                    ? "xmark.circle.fill"
                                    : "checkmark.circle.fill"
                            )
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(state.uploadMessageText.contains("Error") ? .red : .green)
                            Text(state.uploadMessageText)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                        .padding(25)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(UIColor.systemBackground))
                                .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 5)
                        )
                        .padding(.horizontal, 40)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .zIndex(2)
                    }
                }

                .sheet(isPresented: $state.showInsulinAgeMismatch) {
                    NavigationView {
                        List {
                            Section(header: Text("Discrepancy Detected").foregroundColor(.orange)) {
                                Text(
                                    "The three sources report different insulin ages. Select the correct source — it will be written to both iAPS and Nightscout."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            }
                            Section(header: Text("Available Sources")) {
                                ForEach(PumpConfig.InsulinAgeSource.allCases) { source in
                                    let date: Date? = {
                                        switch source {
                                        case .pump: return state.pumpInsulinAge
                                        case .iaps: return state.iapsInsulinAge
                                        case .nightscout: return state.nightscoutInsulinAge
                                        }
                                    }()
                                    Button {
                                        state.applyInsulinAge(from: source)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(source.rawValue)
                                                .font(.headline)
                                            if let d = date {
                                                Text(ageString(d))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text("Not available")
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .disabled(date == nil)
                                }
                            }
                        }
                        .navigationTitle("Select Insulin Age")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    state.showInsulinAgeMismatch = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
