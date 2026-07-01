import Combine
import SwiftUI
import Swinject

/// Final onboarding step (new + existing users): show this device's recovery token to record, and
/// optionally attach it to an account. The token alone already backs up and restores — an account
/// is a convenience (restore by email/password instead of the token, plus device management), so
/// this screen makes that explicit and never links unless the user deliberately does so.
///
/// Linking is multi-token: it adds this token to the account, but that makes it the account's
/// NEWEST device, so a later restore-by-login pulls this device's backup. Default action is to do
/// nothing (Done), which is why logging in to restore on, say, a simulator can't silently take
/// over your account.
struct RecoveryTokenAccountView: View {
    let resolver: Resolver
    /// Finish onboarding (dismiss the cover).
    let onDone: () -> Void

    @StateObject private var model: Model
    @State private var copied = false

    init(resolver: Resolver, onDone: @escaping () -> Void) {
        self.resolver = resolver
        self.onDone = onDone
        _model = StateObject(wrappedValue: Model(resolver: resolver))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                tokenCard
                disclaimer
                accountSection
            }
            .padding()
            .padding(.bottom, 100) // clear the pinned Done button
        }
        .safeAreaInset(edge: .bottom) { doneBar }
        .interactiveDismissDisabled()
        .onAppear(perform: model.onAppear)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Save your recovery token")
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    // MARK: - Token

    private var tokenCard: some View {
        VStack(spacing: 10) {
            Text(model.token)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            Button {
                UIPasteboard.general.string = model.token
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
            }

            Text("Record this somewhere safe. It's how you restore your settings on a new phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var disclaimer: some View {
        Text("You don't need an account — your recovery token above already backs up and restores your settings. An account just lets you restore with an email and password instead of the token, and manage your devices.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
    }

    // MARK: - Account

    @ViewBuilder private var accountSection: some View {
        if model.linked {
            linkedConfirmation
        } else {
            switch model.mode {
            case .options: accountOptions
            case .link: linkForm
            case .register: registerForm
            }
        }
    }

    private var accountOptions: some View {
        VStack(spacing: 12) {
            Text("Optional: attach this device to an account")
                .font(.subheadline).bold()
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { model.mode = .link } label: {
                optionLabel("Link to an existing account", systemImage: "link")
            }
            Button { model.mode = .register } label: {
                optionLabel("Create an account", systemImage: "person.crop.circle.badge.plus")
            }
        }
    }

    private func optionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .foregroundStyle(.primary)
    }

    private var linkForm: some View {
        VStack(spacing: 14) {
            credentialFields(includeConfirmation: false, showCode: model.needsTwoFactor)
            statusMessage
            actionButton(
                title: model.needsTwoFactor ? "Verify & link" : "Link this device",
                working: model.working,
                workingTitle: "Linking…",
                disabled: model.credentialsIncomplete,
                action: model.link
            )
            backButton
        }
    }

    private var registerForm: some View {
        VStack(spacing: 14) {
            credentialFields(includeConfirmation: true, showCode: false)
            statusMessage
            actionButton(
                title: "Create account",
                working: model.working,
                workingTitle: "Creating…",
                disabled: model.registrationIncomplete,
                action: model.register
            )
            backButton
        }
    }

    private func credentialFields(includeConfirmation: Bool, showCode: Bool) -> some View {
        VStack(spacing: 10) {
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $model.password)
                .textContentType(includeConfirmation ? .newPassword : .password)
            if includeConfirmation {
                SecureField("Confirm password", text: $model.passwordConfirmation)
                    .textContentType(.newPassword)
            }
            if showCode {
                TextField("Authentication code", text: $model.code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
            }
        }
        .textFieldStyle(.roundedBorder)
        .disabled(model.working)
    }

    @ViewBuilder private var statusMessage: some View {
        if let message = model.message {
            Text(message)
                .font(.caption)
                .foregroundStyle(model.messageIsError ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func actionButton(
        title: LocalizedStringKey,
        working: Bool,
        workingTitle: LocalizedStringKey,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if working {
                    ProgressView().tint(.white)
                    Text(workingTitle).font(.headline)
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .disabled(working || disabled)
    }

    private var backButton: some View {
        Button("Back") {
            model.message = nil
            model.mode = .options
        }
        .foregroundStyle(.secondary)
        .disabled(model.working)
    }

    private var linkedConfirmation: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Device linked")
                .font(.headline)
            Text("This device is now attached to \(model.linkedEmail). You can restore it by logging in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var doneBar: some View {
        Button(action: onDone) {
            Text(model.linked ? "Done" : "Finish without an account")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(model.linked ? Color.accentColor : Color(.secondarySystemBackground)))
                .foregroundStyle(model.linked ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .padding()
        .background(.regularMaterial)
    }
}

extension RecoveryTokenAccountView {
    final class Model: ObservableObject {
        @Published var token = ""
        @Published var mode: Mode = .options
        @Published var working = false
        @Published var linked = false
        @Published var linkedEmail = ""

        @Published var email = ""
        @Published var password = ""
        @Published var passwordConfirmation = ""
        @Published var code = ""
        @Published var needsTwoFactor = false
        @Published var message: String?
        @Published var messageIsError = false

        enum Mode { case options, link, register }

        private let resolver: Resolver
        private var lifetime = Set<AnyCancellable>()
        private var nudged = false

        init(resolver: Resolver) {
            self.resolver = resolver
            token = resolver.resolve(Keychain.self)?.getIdentifier() ?? ""
        }

        var credentialsIncomplete: Bool {
            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
        }

        var registrationIncomplete: Bool {
            credentialsIncomplete || passwordConfirmation.isEmpty
        }

        /// Nudge a forced settings upload so the device is registered server-side (an AppDevice
        /// row) before the user tries to link/register — it only uploads if Online Backup is on,
        /// which is also the only case where a token is worth linking. Best-effort, once.
        func onAppear() {
            guard !nudged else { return }
            nudged = true
            resolver.resolve(NightscoutManager.self)?.uploadProfileAndSettings(true)
        }

        func link() {
            guard !credentialsIncomplete else { return }
            working = true
            message = nil
            messageIsError = false

            Database(token: "").linkAccount(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                code: needsTwoFactor ? code : nil,
                token: token
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    self.working = false
                    guard case let .failure(error) = completion else { return }
                    self.messageIsError = true
                    switch error {
                    case .twoFactorRequired:
                        self.needsTwoFactor = true
                        self.messageIsError = false
                        self.message = NSLocalizedString("Enter the code from your authenticator app.", comment: "")
                    case .invalidTwoFactor:
                        self.message = NSLocalizedString("That code didn't match. Please try again.", comment: "")
                    case .invalidCredentials:
                        self.message = NSLocalizedString("Email or password is incorrect.", comment: "")
                    case .tokenTaken:
                        self.message = NSLocalizedString("This device is already linked to another account.", comment: "")
                    case .tokenNotFound:
                        self.message = NSLocalizedString("This device hasn't finished its first backup yet. Make sure Online Backup is on, then try again in a moment.", comment: "")
                    case .invalidToken:
                        self.message = NSLocalizedString("This device's recovery token looks invalid.", comment: "")
                    case .unreachable:
                        self.message = NSLocalizedString("Couldn't reach the server. Check your connection and try again.", comment: "")
                    }
                },
                receiveValue: { [weak self] in
                    guard let self else { return }
                    self.linkedEmail = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.linked = true
                }
            )
            .store(in: &lifetime)
        }

        func register() {
            guard !registrationIncomplete else { return }
            guard password == passwordConfirmation else {
                messageIsError = true
                message = NSLocalizedString("Passwords don't match.", comment: "")
                return
            }
            working = true
            message = nil
            messageIsError = false

            Database(token: "").registerAccount(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                passwordConfirmation: passwordConfirmation,
                token: token
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    self.working = false
                    guard case let .failure(error) = completion else { return }
                    self.messageIsError = true
                    switch error {
                    case .emailTaken:
                        self.message = NSLocalizedString("An account with that email already exists. Try linking instead.", comment: "")
                    case .invalidEmail:
                        self.message = NSLocalizedString("That email doesn't look right.", comment: "")
                    case .weakPassword:
                        self.message = NSLocalizedString("Please choose a stronger password (at least 8 characters).", comment: "")
                    case .tokenInvalid:
                        self.message = NSLocalizedString("This device hasn't finished its first backup yet. Make sure Online Backup is on, then try again in a moment.", comment: "")
                    case let .message(text):
                        self.message = text
                    case .unreachable:
                        self.message = NSLocalizedString("Couldn't reach the server. Check your connection and try again.", comment: "")
                    }
                },
                receiveValue: { [weak self] in
                    guard let self else { return }
                    self.linkedEmail = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.linked = true
                }
            )
            .store(in: &lifetime)
        }
    }
}
