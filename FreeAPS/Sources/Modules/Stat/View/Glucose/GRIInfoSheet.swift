import SwiftUI

/// What GRI is, opened by Good & bad days' info button: the first sheet of Statistics (a popover is too small for it).
struct GRIInfoSheet: View {
    /// The sheet's text, its levels in the user's units.
    struct Content: Equatable {
        struct Section: Equatable, Identifiable {
            let id: Int
            /// nil: the text alone
            let title: String?
            let paragraphs: [String]
            /// in the secondary style, after the paragraphs
            let notes: [String]
            /// the zones' tiles: A–E and their values
            var zones: [Zone] = []
        }

        struct Zone: Equatable, Identifiable {
            /// "A"
            let id: String
            /// "0–20"
            let range: String
        }

        let title: String
        /// in bold, first
        let lead: String
        let sections: [Section]

        @MainActor init(bands: StatsBands, units: GlucoseUnits) {
            typealias Format = StatsFormatting
            func level(_ mgdl: Int) -> String {
                Format.glucose(mgdl, units: units) + " " + Format.unit(units)
            }
            // the engine's edges (`GlucoseStatsEngine.gri`): low 54 up to the bottom of `tirRange`, high above its top up to
            // 250, as the integer mg/dL values in them show (54–69 and 181–250; mmol: 3.0–3.8 and 10.1–13.9)
            let veryLow = StatsBands.veryLowBelow
            let veryHigh = StatsBands.veryHighAbove
            let lowRange = veryLow ... Swift.max(veryLow, bands.tirRange.lowerBound - 1)
            let highRange = Swift.min(bands.tirRange.upperBound + 1, veryHigh) ... veryHigh
            title = NSLocalizedString("Glycemia Risk Index (GRI)", comment: "Statistics GRI sheet: its title")
            lead = NSLocalizedString(
                "GRI sums up a day’s glucose in one number from 0 to 100. Lower is better.",
                comment: "Statistics GRI sheet"
            )
            let zoneWidth = GlucoseStatsEngine.griZoneWidth
            sections = [
                Section(
                    id: 0,
                    title: nil,
                    paragraphs: [NSLocalizedString(
                        "It was developed by Klonoff and colleagues (2022). Diabetes clinicians ranked hundreds of glucose profiles by how much each one worried them, and GRI is the formula that best matched their ranking.",
                        comment: "Statistics GRI sheet: where it comes from"
                    )],
                    notes: []
                ),
                Section(
                    id: 1,
                    title: NSLocalizedString("The formula", comment: "Statistics GRI sheet: a section"),
                    paragraphs: [NSLocalizedString(
                        "GRI = 3.0 × very low + 2.4 × low + 1.6 × very high + 0.8 × high, each as a % of the time with CGM data. It is capped at 100.",
                        comment: "Statistics GRI sheet: the formula"
                    )],
                    notes: []
                ),
                Section(
                    id: 2,
                    title: NSLocalizedString("The ranges", comment: "Statistics GRI sheet: a section"),
                    paragraphs: [
                        String(
                            format: NSLocalizedString(
                                "Very low: below %@",
                                comment: "Statistics GRI sheet: a range (\"54 mg/dL\")"
                            ),
                            level(veryLow)
                        ),
                        String(
                            format: NSLocalizedString("Low: %@", comment: "Statistics GRI sheet: a range (\"54–69 mg/dL\")"),
                            Format.range(lowRange, units: units) + " " + Format.unit(units)
                        ),
                        String(
                            format: NSLocalizedString("High: %@", comment: "Statistics GRI sheet: a range (\"181–250 mg/dL\")"),
                            Format.range(highRange, units: units) + " " + Format.unit(units)
                        ),
                        String(
                            format: NSLocalizedString(
                                "Very high: above %@",
                                comment: "Statistics GRI sheet: a range (\"250 mg/dL\")"
                            ),
                            level(veryHigh)
                        )
                    ],
                    notes: []
                ),
                Section(
                    id: 3,
                    title: NSLocalizedString("The two components", comment: "Statistics GRI sheet: a section"),
                    paragraphs: [
                        NSLocalizedString("Hypo component: very low + 0.8 × low", comment: "Statistics GRI sheet"),
                        NSLocalizedString("Hyper component: very high + 0.5 × high", comment: "Statistics GRI sheet")
                    ],
                    notes: [NSLocalizedString(
                        "GRI = 3.0 × hypo + 1.6 × hyper: time spent low counts about twice as much as time spent high, and very low most of all.",
                        comment: "Statistics GRI sheet: the components' weights"
                    )]
                ),
                Section(
                    id: 4,
                    title: NSLocalizedString("The zones", comment: "Statistics GRI sheet: a section"),
                    paragraphs: [],
                    notes: [NSLocalizedString(
                        "Zones: A 0–20 · B 21–40 · C 41–60 · D 61–80 · E 81–100. Zone A is the lowest risk.",
                        comment: "Statistics GRI sheet: the zones"
                    )],
                    // on the whole-number GRI, an edge in the zone below it (`GlucoseStatsEngine.griZone`)
                    zones: ["A", "B", "C", "D", "E"].enumerated().map { index, letter in
                        Zone(id: letter, range: "\(index == 0 ? 0 : index * zoneWidth + 1)–\((index + 1) * zoneWidth)")
                    }
                ),
                Section(
                    id: 5,
                    title: nil,
                    paragraphs: [],
                    notes: [
                        String(
                            format: NSLocalizedString(
                                "GRI always uses these standard ranges, not your Statistics range (%@). Changing your range doesn’t change a day’s GRI or its group.",
                                comment: "Statistics GRI sheet: the user's range (\"70–145 mg/dL\")"
                            ),
                            Format.inRangeLabel(bands: bands, units: units)
                        ),
                        NSLocalizedString(
                            "GRI was designed for 14 days or more. Here it is worked out for each day, to rank the days against each other.",
                            comment: "Statistics GRI sheet: GRI of a single day"
                        )
                    ]
                )
            ]
        }
    }

    let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatsCard {
                        Text(content.lead)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let first = content.sections.first {
                            paragraphs(first)
                        }
                    }
                    ForEach(content.sections.dropFirst()) { section in
                        StatsCard {
                            if let title = section.title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            paragraphs(section)
                            if section.zones.isNotEmpty {
                                zones(section.zones)
                            }
                        }
                    }
                }
                .statsPageContent()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Statistics GRI sheet: closes it")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private func paragraphs(_ section: Content.Section) -> some View {
        ForEach(section.paragraphs, id: \.self) { paragraph in
            Text(paragraph)
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(section.notes, id: \.self) { note in
            Text(note)
                .statsNote()
        }
    }

    private func zones(_ zones: [Content.Zone]) -> some View {
        HStack(spacing: 2) {
            ForEach(zones) { zone in
                VStack(spacing: 1) {
                    Text(zone.id)
                        .font(.subheadline.weight(.bold))
                    Text(zone.range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
