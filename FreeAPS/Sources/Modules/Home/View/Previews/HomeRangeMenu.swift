import SwiftUI

/// A Home card's header row: the title, its range's name muted after it (" · 24 h"; and a detail muted after that, " ·
/// 70–180 mg/dL", the stats bar's glucose range, as much of it as fits), and the values with the chevron at the end. Outside the card's
/// button: a tap on the title or the values opens what the card's button opens. The cards with choices take them on a
/// long-press (`.contextMenu` on the card, `HomeRootView`). At least 44 pt tall: the cards' paddings above and below it are trimmed for it, so nothing overlaps.
struct HomeCardHeader<Values: View>: View {
    let title: String
    /// after the title, muted: " · 24 h"
    let rangeLabel: String
    /// after the range and a separator, muted: " · 70–180 mg/dL"
    let detail: String?
    /// the detail where it doesn't fit: "70–180"; where neither fits, the title and the range alone (never a stub,
    /// "7…")
    let shortDetail: String?
    /// the card's button's action
    let open: () -> Void
    /// the card shows another range than its setting (a pick, up to its read): the values dimmed
    let isStale: Bool
    /// before the chevron
    let values: () -> Values

    init(
        title: String,
        rangeLabel: String,
        detail: String? = nil,
        shortDetail: String? = nil,
        open: @escaping () -> Void,
        isStale: Bool = false,
        @ViewBuilder values: @escaping () -> Values
    ) {
        self.title = title
        self.rangeLabel = rangeLabel
        self.detail = detail
        self.shortDetail = shortDetail
        self.open = open
        self.isStale = isStale
        self.values = values
    }

    var body: some View {
        HStack(spacing: 8) {
            heading
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                // the values never truncate: the title does
                .layoutPriority(1)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                values()
                    .fixedSize()
                    .opacity(isStale ? HomeCardStale.opacity : 1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
        }
        .frame(minHeight: HomeCardMetrics.headerMinHeight)
        // above the card's button below it, should their frames ever meet
        .zIndex(1)
    }

    /// "In range · 24 h · 70–180 mg/dL", the range and the detail muted; "Insulin · Today"
    @ViewBuilder private var heading: some View {
        if let detail {
            // the first that fits whole (larger text): the detail, without its unit, none
            ViewThatFits(in: .horizontal) {
                titled(detail)
                titled(shortDetail ?? detail)
                titleAndRange
            }
        } else {
            titleAndRange
        }
    }

    /// "Insulin · Today"
    private var titleAndRange: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(verbatim: " · " + rangeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "In range · 24 h · 70–180 mg/dL": the detail after a separator, so it doesn't read as part of the range
    /// ("24 h 70")
    private func titled(_ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            titleAndRange
            Text(verbatim: " · ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A card's numbers while they are of another range than its setting (a pick, up to the card's read, or a failed read:
/// the card keeps the last one).
enum HomeCardStale {
    static let opacity = 0.4
}

enum HomeCardMetrics {
    /// the header row's height at least (the cards' paddings around it are trimmed for it)
    static let headerMinHeight: CGFloat = 44
}
