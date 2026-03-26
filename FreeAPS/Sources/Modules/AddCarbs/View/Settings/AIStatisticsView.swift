import Foundation
import SlideButton
import SwiftUI

struct AIStatisticsView: View {
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
