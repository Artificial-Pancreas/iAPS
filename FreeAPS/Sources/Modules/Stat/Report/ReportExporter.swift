import SwiftUI

extension Stat {
    /// What a report takes from the Statistics screen: the provider, the user's units, the period on screen.
    struct ReportContext {
        let source: any ReportDataSource
        let userUnits: GlucoseUnits
        let hbA1cUnit: HbA1cUnit
        /// the current `individualAdjustmentFactor`
        let carbEquivalentFactor: Double
        /// the period the view on screen shows
        let screenPeriod: StatsPeriod

        func request(_ options: ReportOptions, parts: [ReportPart]? = nil) -> ReportRequest {
            ReportRequest(
                period: options.period,
                parts: parts ?? options.orderedParts,
                units: options.units.printed(userUnits: userUnits),
                hbA1cUnit: hbA1cUnit,
                paper: options.paper,
                summary: options.summary,
                carbEquivalentFactor: carbEquivalentFactor
            )
        }
    }

    /// Where a report was asked for: its progress, its failure and its preview belong there.
    enum ReportOrigin: Hashable, Sendable {
        /// the Reports screen's "Create report"
        case screen
        /// a view's "Export PDF" (`ReportExportButton`)
        case part(ReportPart)

        var isScreen: Bool { self == .screen }
    }

    /// Makes a report and hands its file to the preview: the data read off the main actor (`ReportBuilder`), the pages
    /// written one per run loop turn (`ReportPDFWriter`), cancellable; Statistics going down cancels it (`cancel`).
    /// The files hold health data: they live under one directory (`parent`), emptied when the exporter is made, when
    /// a report starts and when the preview is dismissed (`preview` back to nil).
    @MainActor final class ReportExporter: ObservableObject {
        /// the origin of the report being made; nil when none is
        @Published private(set) var running: ReportOrigin?
        /// 0...1 while running
        @Published private(set) var progress: Double = 0
        /// why the last report wasn't made, and where it was asked for; nil while running and after a success
        @Published private(set) var failure: (origin: ReportOrigin, text: String)?
        /// the report shown (`quickLookPreview`, `previewBinding`); set back to nil by its dismissal
        @Published private(set) var preview: (origin: ReportOrigin, url: URL)?

        /// the Statistics screen's (`Stat.StateModel.reportContext`); nil once it is gone
        var context: (@MainActor() -> ReportContext?)?
        let preferences: ReportPreferences
        /// the reports' directory
        let parent: URL
        /// the days' calendar; tests pass a fixed one
        let calendar: @MainActor() -> Calendar

        /// nonisolated(unsafe) for the deinit only
        nonisolated(unsafe) private var task: Task<Void, Never>?
        /// moved on by every start and cancel: a run's late progress and result are its own only
        private var run = 0

        init(
            preferences: ReportPreferences = ReportPreferences(),
            parent: URL = ReportPDFWriter.defaultParent,
            calendar: @escaping @MainActor() -> Calendar = { .current }
        ) {
            self.preferences = preferences
            self.parent = parent
            self.calendar = calendar
            // whatever an earlier run of the app left behind
            ReportPDFWriter.removeAll(in: parent)
        }

        deinit {
            // gone with Statistics: the writer stops before its next page and removes its output
            task?.cancel()
        }

        var isRunning: Bool { running != nil }

        func failure(at origin: ReportOrigin) -> String? {
            failure?.origin == origin ? failure?.text : nil
        }

        /// The report of the options: every selected part (the Reports screen).
        func export(_ options: ReportOptions) {
            guard let context = context?() else { return }
            start(context.request(options), source: context.source, origin: .screen)
        }

        /// One part alone, for the period on screen (the nearest one a report offers), with the saved units, paper and
        /// the part's saved settings.
        func export(part: ReportPart) {
            guard let context = context?() else { return }
            var options = preferences.options(userUnits: context.userUnits)
            options.period = ReportOptions.period(nearest: context.screenPeriod)
            start(context.request(options, parts: [part]), source: context.source, origin: .part(part))
        }

        /// Stops the report being made (Cancel, the Reports screen popped, Statistics going down); a report shown
        /// stays.
        func cancel() {
            run += 1
            task?.cancel()
            task = nil
            running = nil
            progress = 0
        }

        /// The view changed (a tab, a period): a failure said under the old one goes.
        func clearFailure() {
            if failure != nil {
                failure = nil
            }
        }

        /// The preview's binding for a presenter: the Reports screen's sees the reports made there, the root's the
        /// views' own, so the two never present the same file.
        func previewBinding(screen: Bool) -> Binding<URL?> {
            Binding(
                get: { [weak self] in
                    guard let preview = self?.preview, preview.origin.isScreen == screen else { return nil }
                    return preview.url
                },
                set: { [weak self] url in
                    guard let self, url == nil, let preview = self.preview, preview.origin.isScreen == screen else { return }
                    self.preview = nil
                    ReportPDFWriter.removeAll(in: self.parent)
                }
            )
        }

        private func start(_ request: ReportRequest, source: any ReportDataSource, origin: ReportOrigin) {
            cancel()
            preview = nil
            failure = nil
            ReportPDFWriter.removeAll(in: parent)
            running = origin
            let run = self.run
            let parent = self.parent
            let calendar = self.calendar()
            task = Task { [weak self] in
                let result: Result<ReportPDFWriter.Output, Error>
                do {
                    let data = try await ReportBuilder.build(request, source: source)
                    try Task.checkCancellation()
                    let output = try await ReportPDFWriter.write(data, parent: parent, calendar: calendar) { done, total in
                        guard let self, self.run == run else { return }
                        self.progress = total > 0 ? Double(done) / Double(total) : 0
                    }
                    result = .success(output)
                } catch {
                    result = .failure(error)
                }
                guard let self, self.run == run else {
                    // cancelled, replaced or its owner gone: nothing of it stays
                    if case let .success(output) = result {
                        try? FileManager.default.removeItem(at: output.directory)
                    }
                    return
                }
                self.finished(result, origin: origin)
            }
        }

        /// The current run ended, however: it is no longer running.
        private func finished(_ result: Result<ReportPDFWriter.Output, Error>, origin: ReportOrigin) {
            task = nil
            running = nil
            progress = 0
            switch result {
            case let .success(output):
                preview = (origin, output.url)
            case let .failure(error):
                if error is CancellationError { return }
                switch error as? ReportError {
                case .noData:
                    failure = (origin, NSLocalizedString("No CGM data in this period", comment: ""))
                case .nothingSelected:
                    failure = (
                        origin,
                        NSLocalizedString("Select at least one part.", comment: "Reports screen: no part is selected")
                    )
                case nil,
                     .notWritten:
                    warning(.service, "Report: the PDF couldn't be created", error: error)
                    failure = (
                        origin,
                        NSLocalizedString("The report couldn't be created.", comment: "Reports screen: making the PDF failed")
                    )
                }
            }
        }
    }
}

extension Stat.StateModel {
    /// What a report takes from the screen as it is now.
    var reportContext: Stat.ReportContext {
        let appSettings = appCoordinator.settings.value
        return Stat.ReportContext(
            source: provider,
            userUnits: settings.units,
            hbA1cUnit: settings.hbA1cUnit,
            carbEquivalentFactor: (appSettings.individualAdjustmentFactor as NSDecimalNumber).doubleValue,
            screenPeriod: period
        )
    }
}

private struct ReportExporterKey: EnvironmentKey {
    static let defaultValue: Stat.ReportExporter? = nil
}

extension EnvironmentValues {
    /// The Statistics screen's report exporter (`ReportExportButton`); nil outside it.
    var reportExporter: Stat.ReportExporter? {
        get { self[ReportExporterKey.self] }
        set { self[ReportExporterKey.self] = newValue }
    }
}
