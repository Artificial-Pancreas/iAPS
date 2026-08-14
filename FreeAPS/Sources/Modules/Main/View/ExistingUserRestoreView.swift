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

    private var isBusy: Bool {
        switch model.state {
        case .done,
             .working: true
        default: false
        }
    }

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
        .onChange(of: model.state) {
            if case let .done(token) = model.state {
                onDone(token)
            }
        }
    }

    @ViewBuilder private var centeredContent: some View {
        switch model.state {
        case .done,
             .entry,
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
                Text(
                    model.usesLogin
                        ? "Log in to your online backup account to restore your OpenAPS preferences and app settings."
                        :
                        "Enter the recovery token from your previous iAPS install to restore your OpenAPS preferences and app settings from your online backup."
                )
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
            .disabled(isBusy)
            .padding(.horizontal)

            if model.usesLogin {
                loginForm
            } else {
                tokenForm
            }

            Button("Back", action: onBack)
                .disabled(isBusy)
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
                    .disabled(isBusy)
                Text("Find this on your old phone under iAPS → Settings → Sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button(action: model.restore) {
                HStack {
                    if isBusy {
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
            .disabled(isBusy || model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .disabled(isBusy)
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
                    if isBusy {
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
            .disabled(
                isBusy
                    || model.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.password.isEmpty
            )
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
    @MainActor final class Model: ObservableObject {
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

        enum Phase: Equatable {
            case entry
            case working
            case failed(String)
            case done(String)
        }

        private let settingsManager: SettingsManager
        private let contactTrickManager: ContactTrickManager
        private let basalProfileStorage: BasalProfileStorage
        private let carbRatioScheduleStorage: CarbRatioScheduleStorage
        private let isfScheduleStorage: IsfScheduleStorage
        private let bgTargetsScheduleStorage: BgTargetsScheduleStorage

        private let coreDataStorage = CoreDataStorage()

        init(resolver: Resolver) {
            settingsManager = resolver.resolve(SettingsManager.self)!
            contactTrickManager = resolver.resolve(ContactTrickManager.self)!
            basalProfileStorage = resolver.resolve(BasalProfileStorage.self)!
            carbRatioScheduleStorage = resolver.resolve(CarbRatioScheduleStorage.self)!
            isfScheduleStorage = resolver.resolve(IsfScheduleStorage.self)!
            bgTargetsScheduleStorage = resolver.resolve(BgTargetsScheduleStorage.self)!
        }

        func reset() {
            state = .entry
        }

        func restore() {
            Task {
                let token = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !token.isEmpty else {
                    state = .failed(NSLocalizedString("Enter your recovery token.", comment: ""))
                    return
                }
                await runRestore(token: token)
            }
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

            Task {
                do {
                    let database = Database(userToken: StaticUserToken("")) // workaround for a no-token call
                    let token = try await database.fetchAccountToken(
                        email: email,
                        password: password,
                        code: needsTwoFactor ? code : nil
                    )
                    await self.runRestore(token: token)
                } catch {
                    self.state = .entry
                    self.loginMessageIsError = true
                    guard let error = error as? AccountLoginError else {
                        self.loginMessage = error.localizedDescription
                        return
                    }
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
                        self.loginMessage = NSLocalizedString(
                            "Couldn't reach the server. Check your connection and try again.",
                            comment: ""
                        )
                    }
                }
            }
        }

        /// Shared restore pipeline, entered with a token from either the token field or a
        /// successful account login. Preferences + settings gate the restore (all-or-nothing —
        /// a fresh install must never end up half-restored); the pump config, Contact Trick and
        /// profile schedules ride along best-effort. The flow only advances (via the `.done` phase)
        /// once every write has landed — advancing is what deallocates this Model, so the calling
        /// Task must keep retaining it to finish in-flight work (the dealloc-cancel bug the old
        /// flow hit).
        private func runRestore(token: String) async {
            state = .working

            let database = Database(userToken: StaticUserToken(token))

            // The pump config (DIA / max bolus / max basal + insulin concentration) is best-effort:
            // it rides an optional pump-settings row older installs may never have uploaded, so its
            // failure resolves to an empty config rather than failing the whole restore.

            do {
                let preferences = try await database.fetchPreferences("default")
                let settings = try await database.fetchSettings("default")
                let pumpConfig = (try? await database.fetchPumpConfig("default")) ??
                    PumpRestoreConfig(settings: nil, concentration: nil)

                // Preferences: oref re-reads preferences.json from disk each run, so a file
                // write applies on the next loop.
                await settingsManager.updatePreferences(preferences)

                // App settings: route through SettingsManager so the change applies live (its
                // didSet persists + publishes) rather than being shadowed by the already-loaded
                // in-memory settings. Fall back to a raw file write.
                await settingsManager.updateSettings(settings)

                // Pump settings (DIA / max bolus / max basal) → settings.json. The insulin
                // concentration lives in CoreData, not in any settings file, so it's written
                // there separately. Both best-effort: a missing value leaves the default.
                if let pumpSettings = pumpConfig.settings {
                    await settingsManager.updatePumpSettings(pumpSettings)
                }
                if let concentration = pumpConfig.concentration, concentration > 0 {
                    await coreDataStorage.saveConcentration(concentration, increment: preferences.bolusIncrement)
                }

                await restoreContactTrick(using: database)
                await restoreAISettings(using: database)
                await restoreProfileSchedules(using: database, units: settings.units)
                state = .done(token)
            } catch {
                state = .failed(NSLocalizedString(
                    "We couldn't find a backup for that token, or the server was unreachable. Check the token and your connection, then try again.",
                    comment: ""
                ))
            }
        }

        /// Best-effort, silent restore of the Contact Trick display config (not dosing): fetch the
        /// backup's contacts and write them to the contact-trick file, then continue. A missing
        /// backup or an empty list is a no-op; `then` runs once the stream completes either way.
        private func restoreContactTrick(using database: Database) async {
            guard let payload = try? await database.fetchContactTrick("default") else { return }
            guard !payload.contacts.isEmpty else { return }
            _ = await contactTrickManager.updateContacts(contacts: payload.contacts)
        }

        /// Best-effort, silent restore of the AI food-search settings, which live in UserDefaults
        /// rather than in any settings file. Each field is applied only if the backup carried it,
        /// so a partial or older payload leaves the rest at their defaults.
        ///
        /// The provider API keys are deliberately not backed up and so aren't restored — the user
        /// re-enters them in Food Search Settings. We're not putting people's billable Claude /
        /// OpenAI / Gemini credentials on a backup server.
        private func restoreAISettings(using database: Database) async {
            guard let payload = try? await database.fetchAISettings("default") else { return }
            guard let ai = payload.settings else { return }
            let d = UserDefaults.standard

            if let v = ai.textSearchProvider, let p = TextSearchProvider(rawValue: v) { d.textSearchProvider = p }
            if let v = ai.barcodeSearchProvider, let p = BarcodeSearchProvider(rawValue: v) {
                d.barcodeSearchProvider = p
            }
            if let v = ai.aiImageProvider, let p = ImageSearchProvider(rawValue: v) { d.aiImageProvider = p }
            if let v = ai.aiTextProvider, let p = AITextProvider(rawValue: v) { d.aiTextProvider = p }
            if let v = ai.nutritionAuthority, let p = NutritionAuthority(rawValue: v) {
                d.userPreferredNutritionAuthorityForAI = p
            }
            if let v = ai.preferredLanguage { d.userPreferredLanguageForAI = v }
            if let v = ai.preferredRegion { d.userPreferredRegionForAI = v }
            if let v = ai.sendSmallerImages { d.shouldSendSmallerImagesToAI = v }
            if let v = ai.aiTextSearchByDefault { d.aiTextSearchByDefault = v }
            if let v = ai.aiAddImageCommentByDefault { d.aiAddImageCommentByDefault = v }
            if let v = ai.aiSavePhotosToLibrary { d.aiSavePhotosToLibrary = v }
            if let v = ai.aiProgressAnimation { d.aiProgressAnimation = v }
        }

        private func restoreProfileSchedules(using database: Database, units: GlucoseUnits) async {
            guard let profileStore = try? await database.fetchProfile("default") else { return }
            guard let profile = profileStore.store["default"] else { return }

            let d = ProfileScheduleDecomposition.decompose(profile, units: units)
            guard d.problems.isEmpty else { return }

            await basalProfileStorage.updateBasalProfile(d.basal)
            await carbRatioScheduleStorage.updateCrSchedule(d.carbRatios)
            await isfScheduleStorage.updateIsfSchedule(d.sensitivities)
            await bgTargetsScheduleStorage.updateBgTargetsSchedule(d.targets)
        }
    }
}
