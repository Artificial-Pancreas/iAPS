import Foundation
import Photos
import SlideButton
import SwiftUI

struct FoodSearchSettingsView: View {
    @ObservedObject private var aiService = ConfigurableFoodAnalysisService.shared
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var state: AddCarbs.StateModel

    @State private var claudeKey: String = ""
    @State private var openAIKey: String = ""
    @State private var googleGeminiKey: String = ""

    @State private var photoLibraryAuthStatus: PHAuthorizationStatus = .notDetermined

    // API Key visibility toggles - start with keys hidden (secure)
    @State private var showClaudeKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var showGoogleGeminiKey: Bool = false

    @State private var imageSearchProvider: ImageSearchProvider = .defaultProvider
    @State private var aiTextProvider: AITextProvider = .defaultProvider
    @State private var textSearchProvider: TextSearchProvider = .defaultProvider
    @State private var barcodeSearchProvider: BarcodeSearchProvider = .defaultProvider
    @State private var preferredNutritionAuthority: NutritionAuthority = .localDefault

    @State private var aiTextSearchByDefault: Bool = false
    @State private var aiAddImageCommentByDefault: Bool = false
    @State private var sendSmallerImages: Bool = false
    @State private var aiSavePhotosToLibrary: Bool = false
    @State private var aiProgressAnimation: Bool = false

    @State private var preferredLanguage: String = ""
    @State private var preferredRegion: String = ""

    @State private var languageOptionsState: [(code: String, name: String)] = []
    @State private var regionOptionsState: [(code: String, name: String)] = []

    @State private var showingStatistics = false

    private func systemLanguageCode() -> String {
        if let first = Locale.preferredLanguages.first {
            let loc = Locale(identifier: first)
            if let lang = loc.language.languageCode?.identifier {
                return lang
            }
        }
        if let lang = Locale.current.language.languageCode?.identifier {
            return lang
        }
        return "en"
    }

    private func systemRegionCode() -> String {
        if let region = Locale.current.region?.identifier {
            return region
        } else if let regionCode = (Locale.current as NSLocale).object(forKey: .countryCode) as? String {
            return regionCode
        }
        return "US"
    }

    private func buildLanguageOptions() {
        let codes = Set(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))
        let locale = Locale.current
        let items: [(String, String)] = codes.compactMap { code -> (String, String)? in
            let id = Locale.identifier(fromComponents: [NSLocale.Key.languageCode.rawValue: code])
            let display = locale.localizedString(forLanguageCode: code) ?? Locale(identifier: id)
                .localizedString(forLanguageCode: code) ?? code
            return (code, display)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        languageOptionsState = items
    }

    private func buildRegionOptions() {
        let codes = Set(Locale.Region.isoRegions.map(\.identifier))
        let locale = Locale.current
        let items: [(String, String)] = codes.compactMap { code -> (String, String)? in
            let display = locale.localizedString(forRegionCode: code) ?? code
            return (code, display)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        regionOptionsState = items
    }

    private func displayName(for code: String, in options: [(code: String, name: String)]) -> String {
        options.first(where: { $0.code == code })?.name ?? code
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Food Search Provider Configuration"),
                ) {
                    if state.ai {
                        Section(header: Text("Medical Disclaimer")) {
                            Text(
                                "AI nutritional estimates are approximations only. Always consult with your healthcare provider for medical decisions. Verify nutritional information whenever possible. Use at your own risk."
                            )
                            .font(.caption)
                            .foregroundColor(.red)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Provider for AI Image Analysis")
                                .font(.title3)

                            Picker("", selection: $imageSearchProvider) {
                                ForEach(ImageSearchProvider.allCases, id: \.self) { provider in
                                    HStack(spacing: 12) {
                                        Text(provider.providerName)
                                            .font(.caption)
                                        if let modelName = provider.modelName {
                                            Text(modelName)
                                                .font(.subheadline)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.15))
                                                .cornerRadius(4)
                                        }

                                        Spacer()

                                        if let fast = provider.fast, fast {
                                            Text("Fast")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                    }
                                    .tag(provider)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Provider for AI Text Analysis")
                                .font(.title3)

                            Picker("", selection: $aiTextProvider) {
                                ForEach(AITextProvider.allCases, id: \.self) { provider in
                                    HStack(spacing: 12) {
                                        Text(provider.providerName)
                                            .font(.caption)
                                        if let modelName = provider.modelName {
                                            Text(modelName)
                                                .font(.subheadline)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.15))
                                                .cornerRadius(4)
                                        }

                                        Spacer()

                                        if let fast = provider.fast, fast {
                                            Text("Fast")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                    }
                                    .tag(provider)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Provider for Text/Voice Search")
                            .font(.title3)

                        Picker("", selection: $textSearchProvider) {
                            ForEach(TextSearchProvider.allCases, id: \.self) { provider in
                                HStack(spacing: 12) {
                                    Text(provider.providerName)
                                        .font(.caption)

                                    Spacer()
                                }
                                .tag(provider)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Provider for Barcode Scanning")
                            .font(.title3)

                        Picker("", selection: $barcodeSearchProvider) {
                            ForEach(BarcodeSearchProvider.allCases, id: \.self) { provider in
                                HStack(spacing: 12) {
                                    Text(provider.providerName)
                                        .font(.caption)

                                    Spacer()
                                }
                                .tag(provider)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    .padding(.vertical, 4)
                }

                if state.ai {
                    Section {
                        APIKeyRow(
                            label: "Claude API Key",
                            hint: "Get an API key at console.anthropic.com.",
                            placeholder: "Enter your Claude API key",
                            text: $claudeKey,
                            isVisible: $showClaudeKey
                        )
                        APIKeyRow(
                            label: "Google Gemini API Key",
                            hint: "Get a free API key at ai.google.dev.",
                            placeholder: "Enter your Google Gemini API key",
                            text: $googleGeminiKey,
                            isVisible: $showGoogleGeminiKey
                        )
                        APIKeyRow(
                            label: "ChatGPT (OpenAI) API Key",
                            hint: "Get an API key at platform.openai.com.",
                            placeholder: "Enter your OpenAI API key",
                            text: $openAIKey,
                            isVisible: $showOpenAIKey
                        )
                    }

                    Section(
                        header: Text("Localization"),
                        footer: Text(
                            "Choose a specific language and region for AI output."
                        )
                    ) {
                        Picker("Nutrition Authority", selection: $preferredNutritionAuthority) {
                            ForEach(NutritionAuthority.allCases, id: \.self) { authority in
                                Text(authority.description).tag(authority)
                            }
                        }

                        NavigationLink {
                            OptionSelectionView(
                                title: "Preferred Language",
                                options: languageOptionsState,
                                selection: $preferredLanguage
                            )
                        } label: {
                            HStack {
                                Text("Preferred Language")
                                Spacer()
                                Text(
                                    preferredLanguage.isEmpty
                                        ? displayName(for: systemLanguageCode(), in: languageOptionsState)
                                        : displayName(for: preferredLanguage, in: languageOptionsState)
                                )
                                .foregroundColor(.secondary)
                            }
                        }

                        NavigationLink {
                            OptionSelectionView(
                                title: "Preferred Region",
                                options: regionOptionsState,
                                selection: $preferredRegion
                            )
                        } label: {
                            HStack {
                                Text("Preferred Region")
                                Spacer()
                                Text(
                                    preferredRegion.isEmpty
                                        ? displayName(for: systemRegionCode(), in: regionOptionsState)
                                        : displayName(for: preferredRegion, in: regionOptionsState)
                                )
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section(
                        header: Text("Default Text Search Method"),
                        footer: Text(
                            "Sets which search method is selected by default when you open the food search view. You can always toggle between AI and database search using the button next to the search field."
                        )
                    ) {
                        Toggle("Default to AI search", isOn: $aiTextSearchByDefault)
                    }

                    Section(
                        header: Text("Image Annotations"),
                        footer: Text(
                            "When enabled, you'll be prompted to add optional text descriptions to food images."
                        )
                    ) {
                        Toggle("Show annotation prompt for images", isOn: $aiAddImageCommentByDefault)
                    }

                    Section(
                        header: Text("Image Processing"),
                        footer: Text(
                            "When enabled, images are resized to a smaller resolution before sending to AI. This reduces data usage and speeds up analysis, but the AI will see less detail."
                        )
                    ) {
                        Toggle("Send smaller images to AI", isOn: $sendSmallerImages)
                    }

                    Section(
                        header: Text("Photo Library"),
                        footer: Text(
                            "When enabled, photos taken will be saved into the iAPS album in your photo library."
                        )
                    ) {
                        switch photoLibraryAuthStatus {
                        case .authorized,
                             .limited:
                            // Permission granted - show toggle
                            Toggle("Save Photos", isOn: $aiSavePhotosToLibrary)

                        case .notDetermined:
                            // Can request permission - show button
                            Button {
                                Task {
                                    let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                                    await MainActor.run {
                                        photoLibraryAuthStatus = newStatus
                                        if newStatus == .authorized || newStatus == .limited {
                                            aiSavePhotosToLibrary = true
                                        }
                                    }
                                }
                            } label: {
                                Label("Enable Photo Library Access", systemImage: "photo.on.rectangle")
                            }

                        case .denied,
                             .restricted:
                            // Permission denied - show explanation and settings button
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Photo library access is required to save images.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Label("Open Settings", systemImage: "gear")
                                }
                            }

                        @unknown default:
                            EmptyView()
                        }
                    }

                    let allStats = AIUsageStatistics.getAllStatistics()
                    if !allStats.isEmpty {
                        Section(
                            header: Text("Usage Statistics"),
                            footer: Text("View performance metrics for AI models you've used.")
                        ) {
                            Button {
                                showingStatistics = true
                            } label: {
                                HStack {
                                    Image(systemName: "chart.bar.fill")
                                        .foregroundColor(.accentColor)
                                    Text("AI Usage Statistics")
                                    Spacer()
                                    Text("\(allStats.count)")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    Section(
                        header: Text("Miscellaneous"),
                    ) {
                        Toggle("AI Progress Animation", isOn: $aiProgressAnimation)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveSettings()
                    } label: {
                        HStack {
                            Text("Save")
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Text("Cancel")
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Food Search Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            readPersistedValues()
            buildLanguageOptions()
            buildRegionOptions()
        }
        .task {
            photoLibraryAuthStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        }
        .sheet(isPresented: $showingStatistics) {
            AIStatisticsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func readPersistedValues() {
        claudeKey = ConfigurableFoodAnalysisService.shared.getAPIKey(for: .claude) ?? ""
        openAIKey = ConfigurableFoodAnalysisService.shared.getAPIKey(for: .openAI) ?? ""
        googleGeminiKey = ConfigurableFoodAnalysisService.shared.getAPIKey(for: .gemini) ?? ""

        preferredLanguage = UserDefaults.standard.userPreferredLanguageForAI ?? ""
        preferredRegion = UserDefaults.standard.userPreferredRegionForAI ?? ""

        imageSearchProvider = UserDefaults.standard.aiImageProvider
        aiTextProvider = UserDefaults.standard.aiTextProvider
        textSearchProvider = UserDefaults.standard.textSearchProvider
        barcodeSearchProvider = UserDefaults.standard.barcodeSearchProvider
        preferredNutritionAuthority = UserDefaults.standard.userPreferredNutritionAuthorityForAI

        aiTextSearchByDefault = UserDefaults.standard.aiTextSearchByDefault
        aiAddImageCommentByDefault = UserDefaults.standard.aiAddImageCommentByDefault
        sendSmallerImages = UserDefaults.standard.shouldSendSmallerImagesToAI
        aiSavePhotosToLibrary = UserDefaults.standard.aiSavePhotosToLibrary
        aiProgressAnimation = UserDefaults.standard.aiProgressAnimation
    }

    private func saveSettings() {
        aiService.setAPIKey(claudeKey, for: .claude)
        aiService.setAPIKey(openAIKey, for: .openAI)
        aiService.setAPIKey(googleGeminiKey, for: .gemini)

        UserDefaults.standard.userPreferredLanguageForAI = preferredLanguage.isEmpty ? nil : preferredLanguage
        UserDefaults.standard.userPreferredRegionForAI = preferredRegion.isEmpty ? nil : preferredRegion

        UserDefaults.standard.aiImageProvider = imageSearchProvider
        UserDefaults.standard.aiTextProvider = aiTextProvider
        UserDefaults.standard.textSearchProvider = textSearchProvider
        UserDefaults.standard.barcodeSearchProvider = barcodeSearchProvider
        UserDefaults.standard.userPreferredNutritionAuthorityForAI = preferredNutritionAuthority

        UserDefaults.standard.aiTextSearchByDefault = aiTextSearchByDefault
        UserDefaults.standard.aiAddImageCommentByDefault = aiAddImageCommentByDefault
        UserDefaults.standard.shouldSendSmallerImagesToAI = sendSmallerImages
        UserDefaults.standard.aiSavePhotosToLibrary = aiSavePhotosToLibrary
        UserDefaults.standard.aiProgressAnimation = aiProgressAnimation

        dismiss()
    }
}

private struct APIKeyRow: View {
    let label: String
    let hint: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString(label, comment: ""))
                        .font(.subheadline)
                    Text(NSLocalizedString(hint, comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            StableSecureField(placeholder: NSLocalizedString(placeholder, comment: ""), text: $text, isSecure: !isVisible)
        }
        .padding(.vertical, 2)
    }
}

private struct StableSecureField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}
