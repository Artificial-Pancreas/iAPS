import Observation
import SwiftUI

// MARK: - The editor

/// The "Which CGM was this?" sheet's input, read when it opens (`Provider.cgmUnknown`), and its writes: the answer saved
/// as entered sessions, or every entered one cleared. Owned by the state model (`Stat.StateModel.cgmUnknownEditor`),
/// which connects the reads and the writes; the report carries it to the Unknown card and the Entered card.
@MainActor @Observable final class CGMUnknownEditor: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded(Stat.CGMUnknownInput)
        /// the readings couldn't be read
        case failed
    }

    private(set) var status: Status = .idle
    private(set) var isSaving = false
    /// moved on by every input that comes in: the sheet fills from it once (cheaper to compare than the input)
    private(set) var loads = 0

    /// set by the state model (`connectCGMUnknownEditor`)
    @ObservationIgnored var load: (@MainActor() async throws -> Stat.CGMUnknownInput)?
    @ObservationIgnored var save: (@MainActor(_ sessions: [CGMSessionRecord], _ replacing: DateInterval?) async -> Bool)?
    @ObservationIgnored var clear: (@MainActor() async -> Bool)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// nonisolated: a stored property's default value
    nonisolated init() {}

    /// one editor per screen: equal to itself only
    nonisolated static func == (lhs: CGMUnknownEditor, rhs: CGMUnknownEditor) -> Bool {
        lhs === rhs
    }

    /// The sheet opened: its input read again (the readings and the sessions may have changed since).
    func open() {
        loadTask?.cancel()
        status = .loading
        let load = self.load
        loadTask = Task { [weak self] in
            do {
                guard let input = try await load?() else { return }
                guard !Task.isCancelled else { return }
                self?.status = .loaded(input)
                self?.loads += 1
            } catch is CancellationError {
                return
            } catch {
                warning(.service, "Statistics: the Unknown CGM readings couldn't be read", error: error)
                guard !Task.isCancelled else { return }
                self?.status = .failed
            }
        }
    }

    /// The sheet closed: its input dropped (it holds every Unknown reading's time).
    func close() {
        loadTask?.cancel()
        loadTask = nil
        status = .idle
    }

    /// Save: the answer's sessions, replacing the entered ones in `replacing`. Returns whether they were saved.
    func commit(_ sessions: [CGMSessionRecord], replacing: DateInterval?) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        return await save?(sessions, replacing) ?? false
    }

    /// Clear what you entered.
    func clearAll() async {
        _ = await clear?()
    }
}

// MARK: - On the cards

/// The Unknown card's and the Entered card's controls: "Which CGM was this?" (the Unknown card's), what the user
/// entered with Change and Clear, the sheet and the confirmation.
struct CGMUnknownControls: View {
    let editor: CGMUnknownEditor
    let entered: Stat.CGMReport.Entered?
    /// the Unknown card's "Which CGM was this?"
    let asks: Bool

    @State private var isSheetShown = false
    @State private var isClearConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if asks {
                button(NSLocalizedString(
                    "Which CGM was this?",
                    comment: "Statistics CGM Unknown: opens the sheet to name the CGM of the Unknown readings"
                )) { isSheetShown = true }
            }
            if let entered {
                Text(entered.text)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    // only for what is in the sheet's 90 days
                    if entered.canChange {
                        button(NSLocalizedString(
                            "Change",
                            comment: "Statistics CGM Unknown: opens the sheet with what the user entered"
                        )) { isSheetShown = true }
                    }
                    button(
                        NSLocalizedString(
                            "Clear what you entered",
                            comment: "Statistics CGM Unknown: removes every session the user entered"
                        ),
                        role: .destructive
                    ) { isClearConfirmed = true }
                }
            }
        }
        .sheet(isPresented: $isSheetShown) {
            CGMUnknownSheet(editor: editor)
        }
        .confirmationDialog(
            NSLocalizedString(
                "Clear what you entered?",
                comment: "Statistics CGM Unknown: the confirmation's title"
            ),
            isPresented: $isClearConfirmed,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString("Clear", comment: "Statistics CGM Unknown: confirms removing what the user entered"),
                role: .destructive
            ) {
                Task { await editor.clearAll() }
            }
        } message: {
            Text(NSLocalizedString(
                "The readings you named go back to Unknown. The recorded CGM sessions stay.",
                comment: "Statistics CGM Unknown: what clearing does"
            ))
        }
    }

    /// The cards' secondary button (`StatsLinkButton`'s look, no chevron).
    private func button(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
    }
}

/// Another pick than Unknown, with sessions the user entered: how many, Change and Clear (on the Overview).
struct CGMEnteredCard: View {
    let entered: Stat.CGMReport.Entered

    var body: some View {
        StatsCardHeader(
            verbatim: NSLocalizedString("Entered by you", comment: "Statistics CGM: the card of the sessions the user entered"),
            detail: ""
        )
        Text(NSLocalizedString(
            "Readings no recorded CGM session covers, named by you. A recorded session always wins over them.",
            comment: "Statistics CGM: what the entered sessions are"
        ))
            .statsNote()
        if let editor = entered.editor {
            CGMUnknownControls(editor: editor, entered: entered, asks: false)
        }
    }
}

// MARK: - The sheet

/// "Which CGM was this?": three ways to name the CGM of the Unknown readings of the last 90 days. One CGM for all; a
/// switch date (one CGM until it, another from it); or sensor by sensor, the probable sensors iAPS found each with a
/// suggested CGM pre-filled. Suggestions are never saved on their own. Save writes entered sessions covering the
/// Unknown readings (`CGMUnknownInference.sessions`), replacing what was entered over them; Cancel discards.
struct CGMUnknownSheet: View {
    let editor: CGMUnknownEditor

    enum Way: Int, CaseIterable, Identifiable {
        case one
        case switched
        case bySensor

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .one: NSLocalizedString("One CGM", comment: "Statistics CGM Unknown sheet: the way, one CGM for all")
            case .switched: NSLocalizedString("A switch", comment: "Statistics CGM Unknown sheet: the way, a switch date")
            case .bySensor: NSLocalizedString("By sensor", comment: "Statistics CGM Unknown sheet: the way, sensor by sensor")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var way = Way.bySensor
    @State private var oneCGM = ""
    @State private var beforeCGM = ""
    @State private var afterCGM = ""
    @State private var switchDate = Date()
    /// by sensor: its CGM's id, "" to leave it Unknown
    @State private var bySensor: [Date: String] = [:]
    /// filled from the input once, when it comes in
    @State private var isFilled = false
    @State private var saveFailed = false
    /// By sensor with every sensor left Unknown, over what was entered: asked first
    @State private var isRemoveConfirmed = false

    var body: some View {
        NavigationStack {
            Form {
                switch editor.status {
                case .idle,
                     .loading:
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                case .failed:
                    Section {
                        Text(NSLocalizedString(
                            "The readings couldn’t be read.",
                            comment: "Statistics CGM Unknown sheet: the read failed"
                        ))
                            .foregroundStyle(.secondary)
                    }
                case let .loaded(input):
                    if let span = input.span {
                        if saveFailed {
                            Section {
                                Text(NSLocalizedString(
                                    "The answer couldn’t be saved.",
                                    comment: "Statistics CGM Unknown sheet: the save failed"
                                ))
                                    .foregroundStyle(.red)
                            }
                        }
                        content(input, span: span)
                    } else {
                        Section {
                            Text(NSLocalizedString(
                                "Every reading of the last 90 days has a recorded CGM.",
                                comment: "Statistics CGM Unknown sheet: no Unknown readings"
                            ))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle(NSLocalizedString(
                "Which CGM was this?",
                comment: "Statistics CGM Unknown sheet: the title"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Statistics CGM Unknown sheet: discards the answer")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "Statistics CGM Unknown sheet: saves the answer")) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { editor.open() }
        .onDisappear { editor.close() }
        .onChange(of: editor.loads) {
            if case let .loaded(input) = editor.status, !isFilled {
                fill(input)
            }
        }
        .confirmationDialog(
            NSLocalizedString(
                "Remove what you entered for these readings?",
                comment: "Statistics CGM Unknown sheet: saving with every sensor left Unknown"
            ),
            isPresented: $isRemoveConfirmed,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString("Remove", comment: "Statistics CGM Unknown sheet: confirms leaving every sensor Unknown"),
                role: .destructive
            ) {
                commit()
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(_ input: Stat.CGMUnknownInput, span: DateInterval) -> some View {
        Section {
            Picker(
                NSLocalizedString("Way", comment: "Statistics CGM Unknown sheet: the way picker's label"),
                selection: $way
            ) {
                ForEach(Way.allCases) { way in
                    Text(way.title).tag(way)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(summary(input, span: span))
        }

        switch way {
        case .one:
            Section {
                cgmPicker(
                    NSLocalizedString("CGM", comment: "Statistics CGM Unknown sheet: the one CGM's picker"),
                    selection: $oneCGM,
                    choices: input.choices,
                    allowsNone: false
                )
            } footer: {
                Text(NSLocalizedString(
                    "Every Unknown reading becomes this CGM’s, sensor by sensor as iAPS found them.",
                    comment: "Statistics CGM Unknown sheet: the one CGM way"
                ))
            }
        case .switched:
            Section {
                cgmPicker(
                    NSLocalizedString("Until", comment: "Statistics CGM Unknown sheet: the CGM before the switch"),
                    selection: $beforeCGM,
                    choices: input.choices,
                    allowsNone: false
                )
                DatePicker(
                    NSLocalizedString("Switched", comment: "Statistics CGM Unknown sheet: the switch's date and time"),
                    selection: $switchDate,
                    in: span.start ... span.end
                )
                cgmPicker(
                    NSLocalizedString("From", comment: "Statistics CGM Unknown sheet: the CGM after the switch"),
                    selection: $afterCGM,
                    choices: input.choices,
                    allowsNone: false
                )
            } footer: {
                Text(NSLocalizedString(
                    "The first CGM’s readings until the date and time, the second’s from it, sensor by sensor as iAPS found them.",
                    comment: "Statistics CGM Unknown sheet: the switch way"
                ))
            }
        case .bySensor:
            bySensorSections(input)
        }
    }

    @ViewBuilder private func bySensorSections(_ input: Stat.CGMUnknownInput) -> some View {
        if input.sensors.isEmpty {
            Section {
                Text(NSLocalizedString(
                    "No run of readings long enough for a sensor: name them with One CGM.",
                    comment: "Statistics CGM Unknown sheet: no probable sensors"
                ))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Button(NSLocalizedString(
                    "Use the suggestions for all",
                    comment: "Statistics CGM Unknown sheet: every sensor's suggested CGM"
                )) {
                    for sensor in input.sensors {
                        bySensor[sensor.id] = sensor.suggestion?.cgmId ?? bySensor[sensor.id] ?? ""
                    }
                }
            } footer: {
                Text(NSLocalizedString(
                    "Suggestions only: 1-minute readings, or a sensor longer than 11 days, suggest a Libre; about 10 days of 5-minute readings a Dexcom. A Libre 2 can read every 5 minutes and a G6 can be restarted, so check each one.",
                    comment: "Statistics CGM Unknown sheet: how the suggestions are made"
                ))
            }
            Section {
                ForEach(input.sensors.reversed()) { sensor in
                    sensorRow(sensor, input: input)
                }
            } header: {
                Text(String(
                    format: NSLocalizedString(
                        "%d probable sensors, newest first",
                        comment: "Statistics CGM Unknown sheet: the sensors' list (12)"
                    ),
                    input.sensors.count
                ))
            } footer: {
                Text(NSLocalizedString(
                    "A sensor is a run of readings between gaps of 30 minutes, jumps in the level across a missed reading or more, and changes of cadence; a dropout under 2 hours is joined again when both parts fit in one sensor’s life. Its start is its first reading less its CGM’s warm-up when the gap before it holds one, else its first reading.",
                    comment: "Statistics CGM Unknown sheet: what a probable sensor is"
                ))
            }
        }
    }

    private func sensorRow(_ sensor: CGMProbableSensor, input: Stat.CGMUnknownInput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Stat.Patches.dayAndTime(sensor.first) + " – " + Stat.Patches.dayAndTime(sensor.last))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if sensor.isCut {
                Text(NSLocalizedString(
                    "Began before the last 90 days: its start isn’t known",
                    comment: "Statistics CGM Unknown sheet: a sensor cut at the start of the readings read"
                ))
                    .statsFootnote()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text([
                CGMFormat.days(sensor.length),
                String(
                    format: NSLocalizedString(
                        "every %d min",
                        comment: "Statistics CGM Unknown sheet: a sensor's median cadence (5)"
                    ),
                    Swift.max(1, Int((sensor.cadence / 60).rounded()))
                ),
                String(
                    format: NSLocalizedString(
                        "%@ readings",
                        comment: "Statistics CGM Unknown sheet: a sensor's readings (\"2,016\")"
                    ),
                    sensor.readings.formatted(.number)
                )
            ].joined(separator: " · "))
                .statsFootnote()
                .monospacedDigit()
            cgmPicker(
                NSLocalizedString("CGM", comment: "Statistics CGM Unknown sheet: a sensor's CGM picker"),
                selection: Binding(
                    get: { bySensor[sensor.id] ?? "" },
                    set: { bySensor[sensor.id] = $0 }
                ),
                choices: input.choices,
                allowsNone: true
            )
            if let line = suggestionLine(sensor, input: input) {
                Text(line)
                    .statsFootnote()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func cgmPicker(
        _ title: String,
        selection: Binding<String>,
        choices: [CGMChoice],
        allowsNone: Bool
    ) -> some View {
        Picker(title, selection: selection) {
            if allowsNone {
                Text(NSLocalizedString(
                    "Leave Unknown",
                    comment: "Statistics CGM Unknown sheet: a sensor's readings stay Unknown"
                )).tag("")
            }
            ForEach(choices) { choice in
                Text(choice.name).tag(choice.cgmId)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Texts

    /// "1,234 Unknown readings, 3 Aug – Mon 12 Oct, 10:20, in the last 90 days · 3 periods entered by you"
    private func summary(_ input: Stat.CGMUnknownInput, span: DateInterval) -> String {
        var text = String(
            format: NSLocalizedString(
                "%1$@ Unknown readings in the last 90 days, %2$@ – %3$@.",
                comment: "Statistics CGM Unknown sheet: the readings (\"1,234\", \"3 Aug\", \"Mon 12 Oct, 10:20\")"
            ),
            input.unknownTimes.count.formatted(.number),
            CGMFormat.day(span.start),
            Stat.Patches.dayAndTime(span.end)
        )
        if input.enteredSessions > 0 {
            text += " " + NSLocalizedString(
                "Saving replaces what you entered for them.",
                comment: "Statistics CGM Unknown sheet: what saving does to the entered sessions"
            )
        }
        return text
    }

    /// "Suggested: Dexcom G7 (possible: about a Dexcom’s 10 days)"; "You entered: …" when it differs.
    private func suggestionLine(_ sensor: CGMProbableSensor, input: Stat.CGMUnknownInput) -> String? {
        func name(_ id: String) -> String {
            input.choices.first { $0.cgmId == id }?.name ?? id
        }
        var lines: [String] = []
        if let suggestion = sensor.suggestion {
            let confidence = switch suggestion.confidence {
            case .likely: NSLocalizedString("likely", comment: "Statistics CGM Unknown sheet: a suggestion's confidence")
            case .possible: NSLocalizedString("possible", comment: "Statistics CGM Unknown sheet: a suggestion's confidence")
            }
            let reason = switch suggestion.reason {
            case .oneMinute: NSLocalizedString(
                    "readings every minute",
                    comment: "Statistics CGM Unknown sheet: why a Libre is suggested"
                )
            case .longerThanADexcom: NSLocalizedString(
                    "longer than a Dexcom lasts",
                    comment: "Statistics CGM Unknown sheet: why a Libre is suggested"
                )
            case .dexcomLength: NSLocalizedString(
                    "about a Dexcom’s 10 days",
                    comment: "Statistics CGM Unknown sheet: why a Dexcom is suggested"
                )
            case .neighbour: NSLocalizedString(
                    "as the sensor next to it",
                    comment: "Statistics CGM Unknown sheet: a suggestion taken from the neighbouring sensor"
                )
            }
            lines.append(String(
                format: NSLocalizedString(
                    "Suggested: %1$@ (%2$@: %3$@)",
                    comment: "Statistics CGM Unknown sheet: a sensor's suggestion (\"Dexcom G7\", \"possible\", \"about a Dexcom’s 10 days\")"
                ),
                name(suggestion.cgmId),
                confidence,
                reason
            ))
        }
        if let entered = input.entered[sensor.id], entered != sensor.suggestion?.cgmId {
            lines.append(String(
                format: NSLocalizedString(
                    "You entered: %@",
                    comment: "Statistics CGM Unknown sheet: the CGM the user entered for a sensor"
                ),
                name(entered)
            ))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: Filling and saving

    private var canSave: Bool {
        guard case let .loaded(input) = editor.status, input.span != nil, !editor.isSaving else { return false }
        switch way {
        case .one: return input.choices.contains { $0.cgmId == oneCGM }
        case .switched: return input.choices.contains { $0.cgmId == beforeCGM } && input.choices.contains { $0.cgmId == afterCGM }
        // every sensor left Unknown only removes what was entered: nothing to save without it
        case .bySensor: return input.sensors.isNotEmpty && (bySensor.values.contains { !$0.isEmpty } || input.enteredSessions > 0)
        }
    }

    /// What was entered, else the suggestions: by sensor the way when there are sensors; the one CGM the most suggested
    /// (else the newest recorded, else the first known); the switch from the first sensor's CGM to the last one's, at the
    /// first sensor of another CGM.
    private func fill(_ input: Stat.CGMUnknownInput) {
        isFilled = true
        var picks: [Date: String] = [:]
        for sensor in input.sensors {
            picks[sensor.id] = input.entered[sensor.id] ?? sensor.suggestion?.cgmId ?? ""
        }
        bySensor = picks
        way = input.sensors.isEmpty ? .one : .bySensor
        let named = input.sensors.compactMap { picks[$0.id].flatMap { $0.isEmpty ? nil : $0 } }
        let counts = Dictionary(named.map { ($0, 1) }, uniquingKeysWith: +)
        let mostNamed = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        oneCGM = mostNamed ?? input.choices.first?.cgmId ?? ""
        beforeCGM = named.first ?? oneCGM
        afterCGM = named.last ?? oneCGM
        let firstOther = input.sensors.first { sensor in
            picks[sensor.id].map { !$0.isEmpty && $0 != beforeCGM } ?? false
        }
        if let span = input.span {
            let middle = span.start.addingTimeInterval(span.duration / 2)
            switchDate = Swift.min(Swift.max(firstOther?.first ?? middle, span.start), span.end)
        }
    }

    private func save() {
        if way == .bySensor, !bySensor.values.contains(where: { !$0.isEmpty }) {
            isRemoveConfirmed = true
        } else {
            commit()
        }
    }

    private func commit() {
        guard case let .loaded(input) = editor.status else { return }
        func choice(_ id: String) -> CGMChoice? {
            input.choices.first { $0.cgmId == id }
        }
        let answer: CGMUnknownAnswer
        switch way {
        case .one:
            guard let one = choice(oneCGM) else { return }
            answer = .one(one)
        case .switched:
            guard let before = choice(beforeCGM), let after = choice(afterCGM) else { return }
            answer = .switched(at: switchDate, before: before, after: after)
        case .bySensor:
            answer = .bySensor(bySensor.compactMapValues(choice))
        }
        let sessions = CGMUnknownInference.sessions(
            for: answer,
            sensors: input.sensors,
            unknownTimes: input.unknownTimes,
            recorded: input.recorded
        )
        saveFailed = false
        Task {
            if await editor.commit(sessions, replacing: input.replaced) {
                dismiss()
            } else {
                saveFailed = true
            }
        }
    }
}
