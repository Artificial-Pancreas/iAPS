import Combine
import SwiftUI
import Swinject

/// Existing-User onboarding step: restore a cloud backup (open-iaps.app) onto a fresh
/// install using the recovery token from the previous install. Phase A restores the two
/// clean, file-backed sections — OpenAPS Preferences and the iAPS app settings — which
/// together carry the bulk of a user's tuning. Profile schedules (basal/ISF/CR) and the
/// CoreData-backed presets are deliberately out of scope here and handled separately.
struct ExistingUserRestoreView: View {
    let resolver: Resolver
    /// Advance the onboarding cover to the next step (Sharing setup).
    let onDone: () -> Void
    /// Return to the Welcome New-/Existing-User choice.
    let onBack: () -> Void

    @StateObject private var model: Model
    @FocusState private var tokenFieldFocused: Bool

    init(resolver: Resolver, onDone: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.resolver = resolver
        self.onDone = onDone
        self.onBack = onBack
        _model = StateObject(wrappedValue: Model(resolver: resolver))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            switch model.state {
            case .entry,
                 .working:
                entry
            case .done:
                done
            case let .failed(message):
                failure(message)
            }

            Spacer()
        }
        .padding()
        .interactiveDismissDisabled()
    }

    // MARK: - Token entry

    private var entry: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Restore your settings")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                Text("Enter the recovery token from your previous iAPS install to restore your OpenAPS preferences and app settings from your online backup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

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
                    }
                    Text(model.state == .working ? "Restoring…" : "Restore my settings")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(model.state == .working || model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)

            Button("Back", action: onBack)
                .disabled(model.state == .working)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Success

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Settings restored")
                .font(.title).bold()
            Text("Your OpenAPS preferences and app settings were restored from your backup. You'll set up online backup for this device on the next step.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onDone) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
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

            Button("Skip and set up fresh", action: onDone)
                .foregroundStyle(.secondary)
        }
    }
}

extension ExistingUserRestoreView {
    final class Model: ObservableObject {
        @Published var token: String = ""
        @Published var state: Phase = .entry

        enum Phase: Equatable {
            case entry
            case working
            case done
            case failed(String)
        }

        private let resolver: Resolver
        private let storage = BaseFileStorage()
        private var lifetime = Set<AnyCancellable>()

        init(resolver: Resolver) {
            self.resolver = resolver
        }

        func reset() {
            state = .entry
        }

        func restore() {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else {
                state = .failed("Enter your recovery token.")
                return
            }

            state = .working
            let database = Database(token: token)

            // All-or-nothing: only persist once BOTH sections have downloaded, so a fresh
            // install never ends up with half-restored state.
            Publishers.Zip(
                database.fetchPreferences("default"),
                database.fetchSettings("default")
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.state = .failed(
                            "We couldn't find a backup for that token, or the server was unreachable. Check the token and your connection, then try again."
                        )
                    }
                },
                receiveValue: { [weak self] preferences, settings in
                    guard let self else { return }

                    // Preferences: oref re-reads preferences.json from disk each run, so a
                    // file write applies on the next loop.
                    self.storage.save(preferences, as: OpenAPS.Settings.preferences)

                    // App settings: route through SettingsManager so the change applies live
                    // (its didSet persists + publishes) rather than being shadowed by the
                    // already-loaded in-memory settings. Fall back to a raw file write.
                    if let manager = self.resolver.resolve(SettingsManager.self) {
                        manager.settings = settings
                    } else {
                        self.storage.save(settings, as: OpenAPS.FreeAPS.settings)
                    }

                    self.state = .done
                }
            )
            .store(in: &lifetime)
        }
    }
}
