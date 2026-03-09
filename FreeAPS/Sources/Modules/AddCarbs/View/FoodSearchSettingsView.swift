import Foundation
import Photos
import SlideButton
import SwiftUI

/// Simple secure field that uses proper SwiftUI components
struct StableSecureField: View {
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

struct FoodSearchSettingsView: View {
    @ObservedObject private var aiService = ConfigurableFoodAnalysisService.shared
    @Environment(\.dismiss) private var dismiss

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

                    footer: Text(
                        "Configure which service handles each type of food search."
                    )
                ) {
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

                // Statistics Section
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

                Section(header: Text("Medical Disclaimer")) {
                    Text(
                        "AI nutritional estimates are approximations only. Always consult with your healthcare provider for medical decisions. Verify nutritional information whenever possible. Use at your own risk."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            StatisticsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private func modelRow(provider: String, model: String) -> some View {
        HStack {
            Text(NSLocalizedString(provider, comment: ""))
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(NSLocalizedString(model, comment: ""))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Statistics Helpers

    struct ProviderStatisticsGroup {
        let provider: AIProvider
        let providerDisplayName: String
        let models: [AIUsageStatistics.Statistics]
    }

    private func groupStatisticsByProvider(_ stats: [AIUsageStatistics.Statistics]) -> [ProviderStatisticsGroup] {
        // Group by provider
        var grouped: [AIProvider: [AIUsageStatistics.Statistics]] = [:]

        for stat in stats {
            // Parse the modelKey to get the provider
            if let model = AIModel(rawValue: stat.modelKey) {
                let provider = model.provider
                grouped[provider, default: []].append(stat)
            }
        }

        // Convert to sorted array
        return grouped.map { provider, models in
            ProviderStatisticsGroup(
                provider: provider,
                providerDisplayName: provider.displayName,
                models: models.sorted { $0.modelKey < $1.modelKey }
            )
        }
        .sorted { $0.providerDisplayName < $1.providerDisplayName }
    }

    private func modelDisplayName(for modelKey: String) -> String {
        guard let model = AIModel(rawValue: modelKey) else {
            return modelKey
        }
        return model.displayName
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

private struct OptionSelectionView: View {
    let title: String
    let options: [(code: String, name: String)]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredOptions: [(code: String, name: String)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.code.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            ForEach(filteredOptions, id: \.code) { item in
                Button {
                    selection = item.code
                    dismiss()
                } label: {
                    HStack {
                        Text(NSLocalizedString(item.name, comment: ""))
                            .foregroundColor(.primary)
                        Spacer()
                        if selection == item.code {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString(title, comment: ""))
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
    }
}

private struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss

    private var allStats: [AIUsageStatistics.Statistics] {
        AIUsageStatistics.getAllStatistics()
    }

    private var groupedStats: [ProviderStatisticsGroup] {
        groupStatisticsByProvider(allStats)
    }

    var body: some View {
        NavigationStack {
            List {
                if allStats.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Statistics Yet")
                                .font(.headline)
                            Text("Statistics will appear here after you use AI models for food analysis.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                } else {
                    ForEach(groupedStats, id: \.provider) { group in
                        Section(header: Text(group.providerDisplayName)) {
                            ForEach(group.models, id: \.key) { model in
                                VStack(alignment: .leading, spacing: 12) {
                                    // Model name header with column labels
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(modelDisplayName(for: model.modelKey))
                                            .font(.headline)
                                            .fontWeight(.bold)

                                        Spacer()

                                        // Column headers
                                        HStack(spacing: 12) {
                                            Text("Count")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 50, alignment: .trailing)

                                            Text("Avg Time")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 60, alignment: .trailing)
                                        }
                                    }
                                    .padding(.bottom, 4)

                                    // Image stats section
                                    if let imageStat = model.imageStat {
                                        VStack(alignment: .leading, spacing: 6) {
                                            StatTypeHeaderWithBadge(
                                                icon: "photo",
                                                label: "Image",
                                                stat: imageStat
                                            )

                                            // Complexity breakdown for image stats
                                            ComplexityBreakdownView(stat: imageStat)
                                                .padding(.leading, 24)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.primary.opacity(0.03))
                                        .cornerRadius(8)
                                    }

                                    // Text stats section
                                    if let textStat = model.textStat {
                                        VStack(alignment: .leading, spacing: 6) {
                                            StatTypeHeaderWithBadge(
                                                icon: "text.alignleft",
                                                label: "Text",
                                                stat: textStat
                                            )

                                            // Complexity breakdown for text stats
                                            ComplexityBreakdownView(stat: textStat)
                                                .padding(.leading, 24)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.primary.opacity(0.03))
                                        .cornerRadius(8)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                                .listRowSeparator(.hidden)
                            }
                        }
                    }

                    Section {
                        VStack(spacing: 16) {
                            SlideButton(styling: .init(indicatorSize: 50, indicatorColor: Color.red), action: {
                                AIUsageStatistics.clearAll()
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Slide to Clear All Statistics")
                                }
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle("AI Model Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helper Types

    struct ProviderStatisticsGroup {
        let provider: AIProvider
        let providerDisplayName: String
        let models: [ModelStats]
    }

    struct ModelStats: Identifiable {
        let id = UUID()
        let modelKey: String
        let imageStat: AIUsageStatistics.Statistics?
        let textStat: AIUsageStatistics.Statistics?

        var key: String { modelKey }
    }

    // MARK: - Helper Functions

    private func groupStatisticsByProvider(_ stats: [AIUsageStatistics.Statistics]) -> [ProviderStatisticsGroup] {
        // Group by provider and model
        var grouped: [AIProvider: [String: (
            image: AIUsageStatistics.Statistics?,
            text: AIUsageStatistics.Statistics?
        )]] = [:]

        for stat in stats {
            if let model = AIModel(rawValue: stat.modelKey) {
                let provider = model.provider
                let modelKey = stat.modelKey

                if grouped[provider] == nil {
                    grouped[provider] = [:]
                }

                var existing = grouped[provider]![modelKey] ?? (image: nil, text: nil)
                if stat.requestType == .image {
                    existing.image = stat
                } else {
                    existing.text = stat
                }
                grouped[provider]![modelKey] = existing
            }
        }

        return grouped.map { provider, models in
            let modelStats = models.map { modelKey, stats in
                ModelStats(
                    modelKey: modelKey,
                    imageStat: stats.image,
                    textStat: stats.text
                )
            }.sorted { $0.modelKey < $1.modelKey }

            return ProviderStatisticsGroup(
                provider: provider,
                providerDisplayName: provider.displayName,
                models: modelStats
            )
        }
        .sorted { $0.providerDisplayName < $1.providerDisplayName }
    }

    private func modelDisplayName(for modelKey: String) -> String {
        guard let model = AIModel(rawValue: modelKey) else {
            return modelKey
        }
        return model.displayName
    }
}

// MARK: - StatTypeHeaderWithBadge Component

private struct StatTypeHeaderWithBadge: View {
    let icon: String
    let label: String
    let stat: AIUsageStatistics.Statistics

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 16)

            Text(NSLocalizedString(label, comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)

            // Success rate badge
            HStack(spacing: 3) {
                Image(
                    systemName: stat.successRate >= 90 ? "checkmark.circle.fill" :
                        stat.successRate >= 70 ? "checkmark.circle" : "exclamationmark.circle"
                )
                .font(.caption2)
                Text(String(format: "%.0f%%", stat.successRate))
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(
                stat.successRate >= 90 ? .green :
                    stat.successRate >= 70 ? .orange : .red
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                (
                    stat.successRate >= 90 ? Color.green :
                        stat.successRate >= 70 ? Color.orange : Color.red
                )
                .opacity(0.15)
            )
            .cornerRadius(4)

            Spacer()

            // Total requests
            Text("\(stat.requestCount) requests")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - ComplexityBreakdownView Component

private struct ComplexityBreakdownView: View {
    let stat: AIUsageStatistics.Statistics

    var body: some View {
        VStack(spacing: 4) {
            // Show breakdown only if we have any complexity data
            if stat.zeroFoodCount > 0 || stat.oneFoodCount > 0 || stat.twoFoodCount > 0 || stat.multipleFoodCount > 0 {
                if stat.zeroFoodCount > 0 {
                    ComplexityRow(
                        icon: "0.circle.fill",
                        label: "No items",
                        count: stat.zeroFoodCount,
                        averageTime: stat.averageZeroFoodProcessingTime
                    )
                }

                if stat.oneFoodCount > 0 {
                    ComplexityRow(
                        icon: "1.circle.fill",
                        label: "Single item",
                        count: stat.oneFoodCount,
                        averageTime: stat.averageOneFoodProcessingTime
                    )
                }

                if stat.twoFoodCount > 0 {
                    ComplexityRow(
                        icon: "2.circle.fill",
                        label: "Two items",
                        count: stat.twoFoodCount,
                        averageTime: stat.averageTwoFoodProcessingTime
                    )
                }

                if stat.multipleFoodCount > 0 {
                    ComplexityRow(
                        icon: "3.circle.fill",
                        label: "Multiple items",
                        count: stat.multipleFoodCount,
                        averageTime: stat.averageMultipleFoodProcessingTime
                    )
                }
            }
        }
    }
}

// MARK: - ComplexityRow Component

private struct ComplexityRow: View {
    let icon: String
    let label: String
    let count: Int
    let averageTime: TimeInterval

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon and label
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 14)

                Text(NSLocalizedString(label, comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 100, alignment: .leading)

            Spacer()

            // Statistics
            HStack(spacing: 12) {
                // Count
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .frame(width: 50, alignment: .trailing)

                // Average time
                Text(String(format: "%.1fs", averageTime))
                    .font(.caption)
                    .foregroundColor(.primary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}
