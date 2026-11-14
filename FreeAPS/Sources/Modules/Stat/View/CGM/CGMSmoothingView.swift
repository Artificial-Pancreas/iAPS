import SwiftUI

/// The CGM topic's Smoothing view: what the replay does, the period, the CGM, the options and the current setting;
/// Analyse runs it (`CGMSmoothingRuns`), with its progress and Cancel; the results are the two tables of each option's
/// change from no smoothing. Nothing here changes the setting.
struct CGMSmoothingView: View {
    let report: Stat.CGMReport
    let runs: CGMSmoothingRuns
    let analyse: () -> Void
    let cancel: () -> Void

    var body: some View {
        let smoothing = report.smoothing
        let status = runs.status(smoothing.key, readingsSeq: smoothing.readingsSeq)
        VStack(spacing: 16) {
            if let unknown = report.unknown {
                StatsCard { CGMUnknownCard(unknown: unknown) }
            }
            if case let .done(result, analysedAt, newerReadings) = status {
                if newerReadings {
                    StatsCard { CGMSmoothingNewerReadings(analysedAt: analysedAt, analyse: analyse) }
                }
                CGMSmoothingResults(
                    tables: CGMSmoothingTables(result, current: smoothing.current, units: report.units),
                    detail: smoothing.detail
                )
            } else {
                StatsCard { CGMSmoothingIntro(smoothing: smoothing, status: status, analyse: analyse, cancel: cancel) }
            }
        }
    }
}

/// A result analysed before readings the content shown has: when, and Analyse again.
private struct CGMSmoothingNewerReadings: View {
    let analysedAt: Date
    let analyse: () -> Void

    var body: some View {
        Text(String(
            format: NSLocalizedString(
                "Analysed at %@; newer readings since.",
                comment: "Statistics CGM Smoothing: the results are older than the readings (\"14:35\")"
            ),
            analysedAt.formatted(date: .omitted, time: .shortened)
        ))
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        StatsLinkButton("Analyse again", action: analyse)
    }
}

/// What the loop saw: the replay's description and facts, then Analyse, its progress, or why it failed.
private struct CGMSmoothingIntro: View {
    let smoothing: Stat.CGMReport.Smoothing
    let status: CGMSmoothingRuns.Status
    let analyse: () -> Void
    let cancel: () -> Void

    var body: some View {
        Text(NSLocalizedString("What the loop saw", comment: "Statistics CGM Smoothing: the analysis card"))
            .statsSectionTitle()
        Text(NSLocalizedString(
            "Replays the period as the loop ran it. At each loop time it takes the 24 hours of readings the loop had, smooths them with each option, thins them to one per 4.5 minutes as oref gets them, and works out the deltas oref works out. Only the values the loop had at that moment count, never ones revised later.",
            comment: "Statistics CGM Smoothing: what the analysis does"
        ))
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        CGMFactsView(facts: smoothing.facts)
        switch status {
        case let .running(progress):
            running(progress)
        case .failed:
            Text(NSLocalizedString(
                "The readings couldn’t be read.",
                comment: "Statistics CGM Smoothing: the analysis's read failed"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            analyseButton
        case .done,
             .idle:
            analyseButton
            Text(NSLocalizedString(
                "Takes a few seconds for 30 days, off the main screen; the other views stay open meanwhile. Nothing is changed: it only compares.",
                comment: "Statistics CGM Smoothing: before the analysis"
            ))
                .statsNote()
        }
    }

    private var analyseButton: some View {
        Button(action: analyse) {
            Text(NSLocalizedString("Analyse", comment: "Statistics CGM Smoothing: starts the analysis"))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func running(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(
                    format: NSLocalizedString(
                        "Replaying %d options",
                        comment: "Statistics CGM Smoothing: the analysis running (8)"
                    ),
                    SmoothingCandidate.all.count
                ))
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(StatsFormatting.percent(fraction: progress))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: Swift.min(Swift.max(progress, 0), 1))
                .tint(Color.accentColor)
            Text(NSLocalizedString(
                "Every option at each loop time, in parallel, off the main screen",
                comment: "Statistics CGM Smoothing: how the analysis runs"
            ))
                .statsNote()
        }
        Button(action: cancel) {
            Text(NSLocalizedString("Cancel", comment: "Statistics CGM Smoothing: stops the analysis"))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The results: the trend the loop saw, against the reference.
private struct CGMSmoothingResults: View {
    let tables: CGMSmoothingTables
    let detail: String

    @ScaledMetric(relativeTo: .footnote) private var trendColumn: CGFloat = 64
    @ScaledMetric(relativeTo: .footnote) private var referenceColumn: CGFloat = 44

    var body: some View {
        StatsCard {
            StatsCardHeader(
                verbatim: NSLocalizedString(
                    "The trend the loop saw",
                    comment: "Statistics CGM Smoothing: the reference-free table"
                ),
                detail: detail
            )
            CGMSmoothingTable(columns: tables.trendColumns, rows: tables.trendRows, columnWidth: trendColumn)
            Text(tables.trendNote)
                .statsNote()
        }
        StatsCard {
            StatsCardHeader(
                verbatim: NSLocalizedString(
                    "Against the reference",
                    comment: "Statistics CGM Smoothing: the table against the reference"
                ),
                detail: NSLocalizedString(
                    "after the fact",
                    comment: "Statistics CGM Smoothing: the reference is known only afterwards"
                )
            )
            CGMSmoothingTable(columns: tables.referenceColumns, rows: tables.referenceRows, columnWidth: referenceColumn)
            if let ranking = tables.ranking {
                CGMCalloutView(callout: ranking)
            }
            Text(tables.referenceNote)
                .statsNote()
        }
    }
}

/// A table of the options: the name column, then fixed columns; no smoothing's row in bold (its own figures), the
/// current setting's tinted with a "Current" badge.
private struct CGMSmoothingTable: View {
    let columns: [CGMSmoothingTables.Column]
    let rows: [CGMSmoothingTables.Row]
    let columnWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(columns) { column in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(column.title)
                        Text(column.unit)
                            .fontWeight(.regular)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: columnWidth, alignment: .trailing)
                }
            }
            .statsColumnHeader()
            ForEach(rows) { row in
                Divider()
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if row.detail != nil || row.isCurrent {
                            HStack(spacing: 4) {
                                if let detail = row.detail {
                                    Text(detail)
                                }
                                if row.isCurrent {
                                    Text(NSLocalizedString(
                                        "Current",
                                        comment: "Statistics CGM Smoothing: the current setting's badge"
                                    ))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .background(Color.accentColor, in: Capsule())
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .fontWeight(row.isBaseline ? .semibold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.footnote)
                .monospacedDigit()
                .padding(.horizontal, row.isCurrent ? 6 : 0)
                .frame(minHeight: 44)
                .background {
                    if row.isCurrent {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    }
                }
            }
        }
    }
}
