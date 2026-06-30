import SwiftUI

/// Read-only, pre-formatted view-model for the profile-restore review. The Model (in the
/// restore flow) builds this from the decomposed backup so this view stays a dumb presentation
/// layer — every value is already a display string. There's no before/after diff: restore only
/// runs at first launch, where the "current" schedules are just one-line defaults, so the
/// review simply presents the incoming schedules for confirmation.
struct ProfileScheduleReview {
    struct Row: Identifiable {
        let id = UUID()
        /// Segment start, "HH:mm".
        let time: String
        /// The incoming value from the backup, pre-formatted (e.g. "0.55 U/hr", "5.5 mmol/L").
        let value: String
    }

    struct ScheduleSection: Identifiable {
        let id = UUID()
        /// e.g. "Basal rates", "Insulin sensitivity (ISF)".
        let title: String
        /// One-line context, e.g. "24 segments · 13.2 U/day".
        let summary: String
        let rows: [Row]
    }

    let sections: [ScheduleSection]
    /// Validation problems that block applying (non-positive ratio/sensitivity, zero total basal).
    let problems: [String]

    var canApply: Bool { problems.isEmpty && !sections.isEmpty }
}

/// Phase B review-before-apply gate: shows the basal / ISF / carb-ratio / target schedules a
/// cloud restore is about to write — per segment — and only writes once the user confirms.
/// Nothing is persisted by this view.
struct ExistingUserProfileReviewView: View {
    let review: ProfileScheduleReview
    let isApplying: Bool
    let onApply: () -> Void
    /// Escape hatch, shown only when the schedules can't be applied (an invalid backup):
    /// continue onboarding and set them up manually rather than being trapped on this screen.
    let onContinueWithout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                if !review.problems.isEmpty {
                    Section {
                        ForEach(review.problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                    } header: {
                        Text("Check these before applying").textCase(nil)
                    }
                }

                ForEach(review.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            HStack(spacing: 10) {
                                Text(row.time)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(row.value)
                                    .fontWeight(.semibold)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                            Text(section.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            footer
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Review your therapy settings")
                .font(.title2).bold()
                .multilineTextAlignment(.center)
            Text("These basal, ISF, carb-ratio and target schedules came from your backup. Review them, then apply. Your pump's basal will sync when you set up the pump.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: onApply) {
                HStack {
                    if isApplying {
                        ProgressView().tint(.white)
                        Text("Applying…").font(.headline)
                    } else {
                        Text("Apply these settings").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(review.canApply ? Color.accentColor : Color.gray)
                )
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(!review.canApply || isApplying)

            // Only when the backup's schedules are invalid and can't be applied — so the user
            // isn't stuck. The normal path has Apply as the single action.
            if !review.canApply {
                Button("Continue without restoring schedules", action: onContinueWithout)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(isApplying)
            }
        }
        .padding()
    }
}
