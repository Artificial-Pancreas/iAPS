import Combine
import CoreData
import SwiftUI
import Swinject

/// Existing-User onboarding step: restore a cloud backup (open-iaps.app) onto a fresh install
/// using the recovery token from the previous install (or an account login that returns one).
///
/// The restore is SILENT and all-or-nothing on its dosing-critical core — OpenAPS Preferences,
/// the iAPS app settings, the pump config (DIA / max bolus / max basal + insulin concentration —
/// a U200 user left at the U100 default would be mis-dosed) and the profile SCHEDULES (basal,
/// ISF, carb ratios, glucose targets). Best-effort extras (Contact Trick display config) ride
/// along but never fail the restore. On success the token is handed back to the flow, which
/// re-enables backup (Sharing) and then restores the CoreData-backed presets in their own step
/// (`RestoreCoreDataStatusView`) — that step is where the user first sees restored data confirmed.
/// Nothing is reviewed here; the real editors are reachable later from the software-setup summary.
struct ExistingUserRestoreView: View {
    let resolver: Resolver
    /// Restore finished — hand the token forward (empty string = the user skipped, so downstream
    /// treats them as a fresh setup with no CoreData preset restore).
    let onDone: (String) -> Void
    /// Return to the Welcome New-/Existing-User choice.
    let onBack: () -> Void

    @StateObject private var model: Model
    @FocusState private var tokenFieldFocused: Bool

    init(resolver: Resolver, onDone: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        self.resolver = resolver
        self.onDone = onDone
        self.onBack = onBack
        _model = StateObject(wrappedValue: Model(resolver: resolver))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            centeredContent
            Spacer()
        }
        .padding()
        .interactiveDismissDisabled()
        .onAppear { model.onComplete = onDone }
    }

    @ViewBuilder private var centeredContent: some View {
        switch model.state {
        case .entry,
             .working:
            entry
        case let .failed(message):
            failure(message)
        }
    }

    // MARK: - Token entry

    private var entry: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Restore your settings")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                Text(model.usesLogin
                    ? "Log in to your online backup account to restore your OpenAPS preferences and app settings."
                    : "Enter the recovery token from your previous iAPS install to restore your OpenAPS preferences and app settings from your online backup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Picker("", selection: $model.usesLogin) {
                Text("Recovery token").tag(false)
                Text("Account login").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(model.state == .working)
            .padding(.horizontal)

            if model.usesLogin {
                loginForm
            } else {
                tokenForm
            }

            Button("Back", action: onBack)
                .disabled(model.state == .working)
                .foregroundStyle(.secondary)
        }
    }

    private var tokenForm: some View {
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Recovery token", text: $model.token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($tokenFieldFocused)
                    .disabled(model.state == .working)
                Text("Find this on your old phone under iAPS → Settings → Sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button(action: model.restore) {
                HStack {
                    if model.state == .working {
                        ProgressView().tint(.white)
                        Text("Restoring…").font(.headline)
                    } else {
                        Text("Restore my settings").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(model.state == .working || model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)
        }
    }

    private var loginForm: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                TextField("Email", text: $model.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                if model.needsTwoFactor {
                    TextField("Authentication code", text: $model.code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(model.state == .working)
            .padding(.horizontal)

            if let message = model.loginMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(model.loginMessageIsError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: model.login) {
                HStack {
                    if model.state == .working {
                        ProgressView().tint(.white)
                        Text("Logging in…").font(.headline)
                    } else {
                        Text("Log in & restore").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(model.state == .working
                || model.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.password.isEmpty)
            .padding(.horizontal)
        }
    }

    // MARK: - Failure

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Restore didn't complete")
                .font(.title2).bold()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try again") { model.reset() }
                .font(.headline)
                .padding(.horizontal)

            // No token to carry forward — proceed as a fresh setup (no CoreData preset restore).
            Button("Skip and set up fresh") { onDone("") }
                .foregroundStyle(.secondary)
        }
    }
}

extension ExistingUserRestoreView {
    final class Model: ObservableObject {
        @Published var token: String = ""
        @Published var state: Phase = .entry

        // Account-login entry path (alternative to typing the recovery token).
        @Published var usesLogin = false
        @Published var email = ""
        @Published var password = ""
        @Published var code = ""
        /// Set once the server reports the account has 2FA — reveals the code field.
        @Published var needsTwoFactor = false
        /// Inline status under the login form (errors / "enter your code").
        @Published var loginMessage: String?
        /// Whether `loginMessage` is an error (red) vs an informational prompt (secondary).
        @Published var loginMessageIsError = false

        /// Invoked once the restore is written, with the token used — the flow advances on this.
        var onComplete: ((String) -> Void)?

        enum Phase: Equatable {
            case entry
            case working
            case failed(String)
        }

        private let resolver: Resolver
        private let storage = BaseFileStorage()
        private var lifetime = Set<AnyCancellable>()
        /// The token the current restore is running with, handed to `onComplete` on success.
        private var activeToken = ""

        init(resolver: Resolver) {
            self.resolver = resolver
        }

        func reset() {
            state = .entry
        }

        func restore() {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else {
                state = .failed(NSLocalizedString("Enter your recovery token.", comment: ""))
                return
            }
            runRestore(token: token)
        }

        /// Authenticate with account credentials and, on success, restore using the returned
        /// token. Honors 2FA: a `two_factor_required` response reveals the code field, and the
        /// user retries with their authenticator/recovery code.
        func login() {
            let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, !password.isEmpty else {
                loginMessage = NSLocalizedString("Enter your email and password.", comment: "")
                loginMessageIsError = true
                return
            }
            loginMessage = nil
            loginMessageIsError = false
            state = .working

            Database(token: "").fetchAccountToken(
                email: email,
                password: password,
                code: needsTwoFactor ? code : nil
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, case let .failure(error) = completion else { return }
                    self.state = .entry
                    self.loginMessageIsError = true
                    switch error {
                    case .twoFactorRequired:
                        self.needsTwoFactor = true
                        self.loginMessageIsError = false
                        self.loginMessage = NSLocalizedString("Enter the code from your authenticator app.", comment: "")
                    case .invalidTwoFactor:
                        self.loginMessage = NSLocalizedString("That code didn't match. Please try again.", comment: "")
                    case .invalidCredentials:
                        self.loginMessage = NSLocalizedString("Email or password is incorrect.", comment: "")
                    case .noDevice:
                        self.loginMessage = NSLocalizedString("No backup is linked to this account yet.", comment: "")
                    case .unreachable:
                        self.loginMessage = NSLocalizedString("Couldn't reach the server. Check your connection and try again.", comment: "")
                    }
                },
                receiveValue: { [weak self] token in
                    self?.runRestore(token: token)
                }
            )
            .store(in: &lifetime)
        }

        /// Shared restore pipeline, entered with a token from either the token field or a
        /// successful account login. Preferences + settings gate the restore (all-or-nothing —
        /// a fresh install must never end up half-restored); the pump config, Contact Trick and
        /// profile schedules ride along best-effort. The flow only advances (via `complete()`)
        /// once every write has landed — advancing is what deallocates this Model, so it stays
        /// alive to finish its in-flight fetches (the dealloc-cancel bug the old flow hit).
        private func runRestore(token: String) {
            state = .working
            activeToken = token
            let database = Database(token: token)

            // The pump config (DIA / max bolus / max basal + insulin concentration) is best-effort:
            // it rides an optional pump-settings row older installs may never have uploaded, so its
            // failure resolves to an empty config rather than failing the whole restore.
            let pumpConfig = database.fetchPumpConfig("default")
                .replaceError(with: PumpRestoreConfig(settings: nil, concentration: nil))
                .setFailureType(to: Swift.Error.self)
                .eraseToAnyPublisher()

            Publishers.Zip3(
                database.fetchPreferences("default"),
                database.fetchSettings("default"),
                pumpConfig
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.state = .failed(NSLocalizedString(
                            "We couldn't find a backup for that token, or the server was unreachable. Check the token and your connection, then try again.",
                            comment: ""
                        ))
                    }
                },
                receiveValue: { [weak self] preferences, settings, pumpConfig in
                    guard let self else { return }

                    // Preferences: oref re-reads preferences.json from disk each run, so a file
                    // write applies on the next loop.
                    self.storage.save(preferences, as: OpenAPS.Settings.preferences)

                    // App settings: route through SettingsManager so the change applies live (its
                    // didSet persists + publishes) rather than being shadowed by the already-loaded
                    // in-memory settings. Fall back to a raw file write.
                    if let manager = self.resolver.resolve(SettingsManager.self) {
                        manager.settings = settings
                    } else {
                        self.storage.save(settings, as: OpenAPS.FreeAPS.settings)
                    }

                    // Pump settings (DIA / max bolus / max basal) → settings.json. The insulin
                    // concentration lives in CoreData, not in any settings file, so it's written
                    // there separately. Both best-effort: a missing value leaves the default.
                    if let pumpSettings = pumpConfig.settings {
                        self.storage.save(pumpSettings, as: OpenAPS.Settings.settings)
                    }
                    if let concentration = pumpConfig.concentration, concentration > 0 {
                        self.saveConcentration(concentration, increment: preferences.bolusIncrement)
                    }

                    // Sequenced best-effort tail — Contact Trick, then the profile schedules —
                    // finishing with complete(). Each `then` weakly captures self so the chain
                    // never retains it past the flow advancing.
                    self.restoreContactTrick(using: database) { [weak self] in
                        self?.restoreProfileSchedules(using: database, units: settings.units) { [weak self] in
                            self?.complete()
                        }
                    }
                }
            )
            .store(in: &lifetime)
        }

        /// Persist the restored insulin concentration as a new `InsulinConcentration` row,
        /// mirroring how the Basal Profile editor records it (most-recent row wins). The
        /// increment comes from the just-restored preferences' bolus increment.
        private func saveConcentration(_ concentration: Double, increment: Decimal) {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            context.perform {
                let row = InsulinConcentration(context: context)
                row.concentration = concentration
                row.incrementSetting = Double(increment)
                row.date = Date.now
                do {
                    try context.save()
                } catch {
                    debug(.apsManager, "Restore: insulin concentration couldn't be saved to CoreData. Error: \(error)")
                }
            }
        }

        /// Best-effort, silent restore of the Contact Trick display config (not dosing): fetch the
        /// backup's contacts and write them to the contact-trick file, then continue. A missing
        /// backup or an empty list is a no-op; `then` runs once the stream completes either way.
        private func restoreContactTrick(using database: Database, then: @escaping () -> Void) {
            database.fetchContactTrick("default")
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in then() },
                    receiveValue: { [weak self] payload in
                        guard let self, !payload.contacts.isEmpty else { return }
                        self.storage.save(payload.contacts, as: OpenAPS.Settings.contactTrick)
                    }
                )
                .store(in: &lifetime)
        }

        /// Fetch the backup profile, decompose it into native schedules and write them silently,
        /// then regenerate the composed profile so the restored values take effect. A missing or
        /// empty profile — or one with validation problems (non-positive ratio/sensitivity, zero
        /// total basal) — is left alone rather than written, so a bad backup can't push unsafe
        /// dosing schedules. Basal isn't pushed to a pump here (there's none yet at restore); it
        /// syncs when the pump is set up. `then` always runs when done.
        private func restoreProfileSchedules(using database: Database, units: GlucoseUnits, then: @escaping () -> Void) {
            database.fetchProfile("default")
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        // No profile on the server (fetch failed) → nothing to restore, still done.
                        if case .failure = completion { then() }
                    },
                    receiveValue: { [weak self] profileStore in
                        guard let self else { return }
                        guard let profile = profileStore.store["default"] else { then(); return }

                        let d = ProfileScheduleDecomposition.decompose(profile, units: units)
                        guard d.problems.isEmpty else { then(); return }

                        self.storage.save(d.basal, as: OpenAPS.Settings.basalProfile)
                        self.storage.save(d.carbRatios, as: OpenAPS.Settings.carbRatios)
                        self.storage.save(d.sensitivities, as: OpenAPS.Settings.insulinSensitivities)
                        self.storage.save(d.targets, as: OpenAPS.Settings.bgTargets)

                        // Regenerate settings/profile.json from the new schedules (the same call the
                        // editors and Autotune config use). Best-effort: continue regardless.
                        if let apsManager = self.resolver.resolve(APSManager.self) {
                            apsManager.makeProfiles()
                                .receive(on: DispatchQueue.main)
                                .sink { _ in then() }
                                .store(in: &self.lifetime)
                        } else {
                            then()
                        }
                    }
                )
                .store(in: &lifetime)
        }

        /// Hand the token to the flow, which advances to the Sharing step.
        private func complete() {
            onComplete?(activeToken)
        }
    }
}
