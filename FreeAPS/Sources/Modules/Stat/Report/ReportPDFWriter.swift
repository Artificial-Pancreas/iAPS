import CoreGraphics
import SwiftUI

/// Writes a report as a vector PDF: each page a print view (`ReportPageView`) drawn by an `ImageRenderer` into a PDF
/// context, the main run loop given a turn between two pages.
@MainActor enum ReportPDFWriter {
    struct Output: Equatable, Sendable {
        /// the PDF
        let url: URL
        /// its own directory, under the parent
        let directory: URL
        let pageCount: Int
    }

    /// layout snaps to whole points, and rules thinner than a point vanish, below this
    private static let rendererScale: CGFloat = 4
    /// between two pages: the run loop redraws the progress and takes a Cancel
    private static let pagePause: UInt64 = 1_000_000

    /// Where every report is written, each in a directory of its own: they hold health data, so the whole directory is
    /// removed whenever no report is shown (`removeAll`).
    nonisolated static var defaultParent: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iAPS-reports", isDirectory: true)
    }

    /// Removes every report written under `parent`.
    nonisolated static func removeAll(in parent: URL) {
        try? FileManager.default.removeItem(at: parent)
    }

    /// "iAPS report 2026-11-08 – 2026-11-21.pdf": the first and last day printed (`ReportData.fileDays`) in the
    /// calendar's time zone
    nonisolated static func fileName(first: Date, last: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "iAPS report \(formatter.string(from: first)) – \(formatter.string(from: last)).pdf"
    }

    /// "5.2.0": the PDF's Creator's and the footer's version
    nonisolated static var appVersion: String {
        Bundle.main.releaseVersionNumber ?? ""
    }

    /// Writes the report into a new directory of its own under `parent`.
    /// Throws `CancellationError` when cancelled between two pages, `Stat.ReportError` when there is nothing to write
    /// or the file can't be created; nothing is left behind then.
    /// - Parameters:
    ///   - calendar: the period's days' (the file's name, the header's dates)
    ///   - progress: called after each page with the pages written and the report's pages
    static func write(
        _ data: Stat.ReportData,
        version: String = ReportPDFWriter.appVersion,
        parent: URL = ReportPDFWriter.defaultParent,
        calendar: Calendar = .current,
        progress: (@MainActor(Int, Int) -> Void)? = nil
    ) async throws -> Output {
        // laid out once: the Days table's rows aren't built again for every page of it
        let layout = data.layout(calendar: calendar)
        let pages = layout.pages
        guard let firstPage = pages.first else { throw Stat.ReportError.nothingSelected }
        let days = data.fileDays(calendar: calendar)
        let fileName = Self.fileName(first: days.first, last: days.last, calendar: calendar)

        let fileManager = FileManager.default
        let directory = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)

        var box = CGRect(origin: .zero, size: firstPage.size)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: String(fileName.dropLast(".pdf".count)),
            kCGPDFContextCreator as String: "iAPS \(version)".trimmingCharacters(in: .whitespaces)
        ]
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            try? fileManager.removeItem(at: directory)
            throw Stat.ReportError.notWritten
        }

        let locale = Locale.current
        let layoutDirection: LayoutDirection = locale.language.characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
        do {
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                if let content = Stat.ReportPageContent(data, page: page, dayRows: layout.dayRows, calendar: calendar) {
                    let chrome = Stat.ReportPageChrome(
                        data,
                        page: page,
                        index: index,
                        count: pages.count,
                        version: version,
                        calendar: calendar,
                        header: content.header
                    )
                    let view = ReportPageView(content: content, chrome: chrome, size: page.size)
                        .environment(\.colorScheme, .light)
                        .environment(\.locale, locale)
                        .environment(\.layoutDirection, layoutDirection)
                        .dynamicTypeSize(.large)
                    let renderer = ImageRenderer(content: view)
                    renderer.proposedSize = ProposedViewSize(page.size)
                    renderer.scale = rendererScale
                    renderer.render { _, draw in
                        var pageBox = CGRect(origin: .zero, size: page.size)
                        let boxData = Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size) as CFData
                        let pageInfo: [String: Any] = [kCGPDFContextMediaBox as String: boxData]
                        context.beginPDFPage(pageInfo as CFDictionary)
                        draw(context)
                        context.endPDFPage()
                    }
                }
                progress?(index + 1, pages.count)
                // a real turn of the main run loop (not only of the executor); throws when cancelled meanwhile
                try await Task.sleep(nanoseconds: pagePause)
            }
        } catch {
            context.closePDF()
            try? fileManager.removeItem(at: directory)
            throw error
        }
        context.closePDF()
        return Output(url: url, directory: directory, pageCount: pages.count)
    }
}
