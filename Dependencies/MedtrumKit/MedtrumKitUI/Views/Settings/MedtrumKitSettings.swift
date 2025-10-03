import LoopKit
import LoopKitUI
import SwiftUI

struct MedtrumKitSettings: View {
    @State private var isSharePresented: Bool = false
    @ObservedObject var viewModel: MedtrumKitSettingsViewModel

    @Environment(\.dismissAction) private var dismiss
    @Environment(\.insulinTintColor) var insulinTintColor
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.appName) private var appName

    var supportedInsulinTypes: [InsulinType]

    var heartbeatModeToggleWarning: ActionSheet {
        let message = viewModel.usingHeartbeatMode ?
            LocalizedString(
                "Currently, you are using a heartbeat mode. This is needed to keep %1$@ running in the background. This might be interesting if your CGM already provides a heartbeat. It is recommended to keep this feature enabled",
                comment: "Message warning heartbeat disable (1: app name)"
            ) :
            LocalizedString(
                "Currently, you are NOT using a heartbeat mode. A heartbeat is needed to keep %1$@ running in the background. It is recommended to keep enable this feature",
                comment: "Message warning heartbeat disable (1: app name)"
            )

        let enableLabel = viewModel.usingHeartbeatMode ?
            LocalizedString("Yes, Disable heartbeat mode", comment: "Button text to disable heartbeat mode") :
            LocalizedString("Yes, Enable heartbeat mode", comment: "Button text to enable heartbeat mode")

        return ActionSheet(
            title: Text(LocalizedString("Toggle heartbeat mode", comment: "Title for toggle heartbeat mode action sheet.")),
            message: Text(String(format: message, appName)),
            buttons: [
                .default(Text(enableLabel)) {
                    self.viewModel.toggleHeartbeat()
                },
                .cancel(Text(LocalizedString("No, Keep as is", comment: "Button text to cancel actionsheet")))
            ]
        )
    }

    var body: some View {
        List {
            Section {
                VStack {
                    PumpImage(is300u: viewModel.is300u)
                    patchLifecycle
                }

                HStack(alignment: .top) {
                    deliveryStatus
                    Spacer()
                    reservoirStatus
                }
                .padding(.bottom, 5)
            }

            Section {
                Button(action: {
                    viewModel.suspendResumeButtonPressed()
                }) {
                    HStack {
                        if viewModel.basalType == .suspended {
                            Text(LocalizedString("Resume delivery", comment: "Resume patch"))
                        } else {
                            Text(LocalizedString("Suspend delivery", comment: "Suspend patch"))
                        }
                        Spacer()
                        if viewModel.isUpdatingSuspend {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState || viewModel.isUpdatingTempBasal || viewModel.isUpdatingSuspend)

                if viewModel.basalType == .tempBasal {
                    Button(action: {
                        viewModel.stopTempBasal()
                    }) {
                        HStack {
                            Text(LocalizedString("Stop temp basal", comment: "Stop temp basal"))
                            Spacer()
                            if viewModel.isUpdatingTempBasal {
                                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            }
                        }
                    }
                    .disabled(viewModel.isUpdatingPumpState || viewModel.isUpdatingTempBasal || viewModel.isUpdatingSuspend)
                }

                Button(action: { viewModel.syncData() }) {
                    HStack {
                        Text(LocalizedString("Sync patch data", comment: "sync pump"))
                        Spacer()
                        if viewModel.isUpdatingPumpState {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState || viewModel.isUpdatingTempBasal || viewModel.isUpdatingSuspend)

                if viewModel.patchState.rawValue < PatchState.active.rawValue && viewModel.patchState != .none {
                    Button(action: { viewModel.toPumpActivation() }) {
                        HStack {
                            Text(LocalizedString("Activate patch", comment: "label for activate patch"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: UIFont.systemFontSize, weight: .bold))
                                .opacity(0.35)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if viewModel.usingHeartbeatMode {
                    Button(action: { viewModel.checkConnection() }) {
                        HStack {
                            if viewModel.isConnected {
                                Text(LocalizedString("Disconnect", comment: "disconnect from patch"))
                            } else {
                                Text(LocalizedString("Reconnect", comment: "reconnect to patch"))
                            }
                            Spacer()
                            if viewModel.isReconnecting {
                                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            }
                        }
                    }
                }

                Button(action: { viewModel.deactivatePatchAction() }) {
                    HStack {
                        Text(LocalizedString("Deactivate Patch", comment: "deactivate patch"))
                            .foregroundStyle(.red)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: UIFont.systemFontSize, weight: .bold))
                            .opacity(0.5)
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Text(LocalizedString("Patch state", comment: "Text for patch state"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.patchStateString)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(LocalizedString("Last sync", comment: "Text for last sync"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    if viewModel.patchLifecycleState != .noPatch {
                        Text(viewModel.dateFormatter.string(from: viewModel.lastSync))
                            .foregroundColor(.secondary)
                    } else {
                        Text("-")
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.usingHeartbeatMode {
                    HStack {
                        Text(LocalizedString("Status", comment: "Text for status")).foregroundColor(Color.primary)
                        Spacer()
                        HStack(spacing: 10) {
                            connectionStatusText
                            connectionStatusIcon
                        }
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString("Configuration", comment: "Configuration section"))) {
                NavigationLink(destination: InsulinTypeSelector(
                    initialValue: viewModel.insulinType,
                    supportedInsulinTypes: supportedInsulinTypes,
                    didConfirm: viewModel.didChangeInsulinType
                )) {
                    HStack {
                        Text(LocalizedString("Insulin Type", comment: "Text for selecting insulin type"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.insulinType.brandName)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: PatchSettingsView(viewModel: viewModel.patchSettingsViewModel)) {
                    Text(LocalizedString("Patch settings", comment: "Text for patch settings view"))
                        .foregroundColor(Color.primary)
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Information",
                comment: "The title for patch/pump information"
            ))) {
                HStack {
                    Text(LocalizedString("Pump base SN", comment: "Text for pumpSN"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.pumpBaseSN)
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture {
                    viewModel.showingHeartbeatWarning = true
                }
                .actionSheet(isPresented: $viewModel.showingHeartbeatWarning) {
                    heartbeatModeToggleWarning
                }
                HStack {
                    Text(LocalizedString("Pump base model", comment: "Text for model"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.model)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(LocalizedString("Patch ID", comment: "Text for activatedAt"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text("\(viewModel.patchId)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(LocalizedString("Patch activated at", comment: "Text for activatedAt"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    if viewModel.patchLifecycleState != .noPatch {
                        Text(viewModel.dateTimeFormatter.string(from: viewModel.patchActivatedAt))
                            .foregroundColor(.secondary)
                    } else {
                        Text("-")
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text(LocalizedString("Patch expires at", comment: "Text for expiresAt"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    if viewModel.patchLifecycleState != .noPatch {
                        Text(viewModel.dateTimeFormatter.string(from: viewModel.patchExpiresAt))
                            .foregroundColor(.secondary)
                    } else {
                        Text("-")
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text(LocalizedString("Battery", comment: "Text for battery voltageB"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.batteryText(for: viewModel.battery))
                        .foregroundColor(.secondary)
                }

                if let sessionToken = viewModel.patchSessionToken {
                    HStack {
                        Text(LocalizedString("Session token", comment: "Text for session token"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(sessionToken)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let previousPatch = viewModel.previousPatch {
                Section(header: SectionHeader(label: LocalizedString(
                    "Previous Patch Details",
                    comment: "label for previous patch details"
                ))) {
                    HStack {
                        Text(LocalizedString("Patch ID", comment: "Text for patchId"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text("\(previousPatch.patchId.toUInt64())")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedString("Patch state", comment: "Text for state"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text((PatchState(rawValue: previousPatch.lastStateRaw) ?? .none).description)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedString("Activated at", comment: "Text for activatedAt"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.dateTimeFormatter.string(from: previousPatch.activatedAt))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedString("Deactivated at", comment: "Text for deactivatedAt"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.dateTimeFormatter.string(from: previousPatch.deactivatedAt))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedString("Battery", comment: "Text for battery voltageB"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.batteryText(for: previousPatch.battery))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(LocalizedString("Share Medtrum patch logs", comment: "Share logs")) {
                    self.isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented, onDismiss: {}, content: {
                    ActivityViewController(activityItems: viewModel.getLogs())
                })

                Button(action: {
                    viewModel.showingDeleteConfirmation = true
                }) {
                    Text(LocalizedString("Delete Pump", comment: "Label for PumpManager deletion button"))
                        .foregroundColor(guidanceColors.critical)
                }
                .actionSheet(isPresented: $viewModel.showingDeleteConfirmation) {
                    removePumpManagerActionSheet(deleteAction: viewModel.pumpRemovalAction)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle(viewModel.pumpName)
    }

    var reservoirStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedString("Insulin Remaining", comment: "Header for insulin remaining on pod settings screen"))
                .foregroundColor(Color(UIColor.secondaryLabel))
            HStack {
                ReservoirView(
                    reservoirLevel: viewModel.reservoirLevel,
                    fillColor: reservoirColor,
                    maxReservoirLevel: viewModel.maxReservoirLevel
                )
                .frame(width: 23, height: 32)
                Text(viewModel.reservoirText(for: viewModel.reservoirLevel))
                    .font(.system(size: 28))
                    .fontWeight(.heavy)
                    .fixedSize()
            }
        }
    }

    var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(deliverySectionTitle)
                .foregroundColor(Color(UIColor.secondaryLabel))

            switch viewModel.basalType {
            case .active,
                 .tempBasal:
                HStack(alignment: .center) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(viewModel.basalRateFormatter.string(from: viewModel.basalRate as NSNumber) ?? "")
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()
                        Text(LocalizedString("U/hr", comment: "Units for showing temp basal rate"))
                            .foregroundColor(.secondary)
                    }
                }
            case .suspended:
                HStack(alignment: .center) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.warning)
                    Text(LocalizedString(
                        "Insulin\nSuspended",
                        comment: "Text shown in insulin delivery space when insulin suspended"
                    ))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            }
        }
    }

    var patchLifecycle: some View {
        VStack {
            switch viewModel.patchLifecycleState {
            case .noPatch:
                HStack {
                    Text(LocalizedString("No active patch", comment: "Text shown when no patch active"))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            case .active:
                HStack {
                    Text(LocalizedString("Age:", comment: "Text shown while patch is active"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    viewModel.patchLifecycleDays.map { days in
                        timeComponent(
                            value: days,
                            units: days == 1 ?
                                LocalizedString("day", comment: "Unit for singular day") :
                                LocalizedString("days", comment: "Unit for plural days")
                        )
                    }
                    viewModel.patchLifecycleHours.map { hours in
                        timeComponent(
                            value: hours,
                            units: hours == 1 ?
                                LocalizedString("hour", comment: "Unit for singular hour") :
                                LocalizedString("hours", comment: "Unit for plural hours")
                        )
                    }
                    viewModel.patchLifecycleMinutes.map { minutes in
                        timeComponent(
                            value: minutes,
                            units: minutes == 1 ?
                                LocalizedString("minute", comment: "Unit for singular minute") :
                                LocalizedString("minutes", comment: "Unit for plural minutes")
                        )
                    }
                }
            case .expired:
                HStack {
                    Text(LocalizedString("Patch expired", comment: "Text shown when patch expired"))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            ProgressView(progress: viewModel.patchLifecycleProgress)
                .padding(.top, -5)
        }
    }

    func timeComponent(value: Int, units: String) -> some View {
        Group {
            Text(String(value))
                .font(.system(size: 24))
                .fontWeight(.heavy)
                .foregroundColor(.primary)
            Text(units)
                .foregroundColor(.secondary)
        }
    }

    private var doneButton: some View {
        Button(LocalizedString("Done", comment: "Button for closing settings"), action: {
            dismiss()
        })
    }

    public var reservoirColor: Color {
        // TODO: Configurable??
        if viewModel.reservoirLevel > (viewModel.maxReservoirLevel * 0.1) {
            return insulinTintColor
        }

        if viewModel.reservoirLevel > 0 {
            return guidanceColors.warning
        }

        return guidanceColors.critical
    }

    var connectionStatusText: some View {
        if viewModel.isConnected {
            return Text(LocalizedString("Connected", comment: "label for connected"))
        }

        if viewModel.isReconnecting {
            return Text(LocalizedString("Reconnecting...", comment: "label for reconnecting"))
        }

        return Text(LocalizedString("Disconnected", comment: "label for disconnected"))
    }

    var connectionStatusIcon: some View {
        let color = viewModel.isReconnecting ? Color.orange : viewModel.isConnected ? Color.green : Color.red

        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    var deliverySectionTitle: String {
        switch viewModel.basalType {
        case .active:
            return LocalizedString("Scheduled Basal", comment: "Title of insulin delivery section")
        case .tempBasal:
            return LocalizedString("Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        case .suspended:
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        }
    }
}
