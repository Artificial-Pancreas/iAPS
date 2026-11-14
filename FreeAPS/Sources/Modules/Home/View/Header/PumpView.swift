import CoreData
import SwiftUI

struct PumpView: View {
    @Environment(AppUIState.self) private var appUIState

    let hideInsulinBadge: Bool
    let timerDate: Date

    @Environment(\.colorScheme) var colorScheme

    private var reservoirFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    @FetchRequest(
        entity: InsulinConcentration.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
    ) var concentration: FetchedResults<InsulinConcentration>

    /// What the header's pump element shows. Decided by `element(info:status:now:currentTimeZone:)`, drawn once below.
    enum Element: Equatable {
        case noPump
        /// a pump that has not been onboarded
        case reconnect
        /// a pod or patch pump without an active pod / patch
        case noPod
        case noPatch
        case device(Device)
    }

    struct Device: Equatable {
        let kind: HeaderPump
        /// nil: not known
        let reservoir: ReservoirReading?
        /// only for a pump that reports its battery
        let batteryPercent: Int?
        /// only for a pod or a patch
        let lifetime: Lifetime?
        let state: DeviceState
        /// the pump's clock is in another time zone than the phone
        let clockOffset: Bool
    }

    /// Seconds, never negative.
    enum Lifetime: Equatable {
        case remaining(TimeInterval)
        /// the time since the expiry
        case expired(TimeInterval)
    }

    /// The most serious of the pump's conditions: the device's icon is dimmed and badged for all but `normal`.
    enum DeviceState: Equatable {
        case normal
        case suspended
        case deliveryUncertain
        /// the pump manager reports a critical status (a pod or patch fault, an occlusion, no insulin, signal loss)
        case critical
    }

    static func element(
        info: PumpDisplayInfo?,
        status: PumpDisplayStatus?,
        now: Date,
        currentTimeZone: TimeZone = .current
    ) -> Element {
        guard let info else { return .noPump }
        guard info.isOnboarded else { return .reconnect }

        let kind = KnownPlugins.headerPump(pluginIdentifier: info.identifier)
        let wearable = kind == .pod || kind == .medtrum

        var lifetime: Lifetime?
        if wearable {
            guard let expiresAt = info.expiresAt else { return kind == .pod ? .noPod : .noPatch }
            let remaining = expiresAt.timeIntervalSince(now)
            lifetime = remaining > 0 ? .remaining(remaining) : .expired(-remaining)
        }

        var batteryPercent: Int?
        if !wearable, let battery = status?.battery, battery.display == true {
            batteryPercent = battery.percent
        }

        return .device(Device(
            kind: kind,
            reservoir: status?.reservoir,
            batteryPercent: batteryPercent,
            lifetime: lifetime,
            state: deviceState(status),
            clockOffset: status.map { $0.timeZone.secondsFromGMT(for: now) }
                .map { $0 != currentTimeZone.secondsFromGMT(for: now) } ?? false
        ))
    }

    static func deviceState(_ status: PumpDisplayStatus?) -> DeviceState {
        guard let status else { return .normal }
        if status.highlight?.level == .critical { return .critical }
        if status.deliveryIsUncertain { return .deliveryUncertain }
        return status.isSuspended ? .suspended : .normal
    }

    /// The empty part of the device's icon, 0 ... 1. A pod's and a patch's icon is not rectangular and has its
    /// inserter at the bottom (hence 120 % and + 10 U, of 200 U); the other pumps' is taken as a 300 U cartridge.
    static func emptyPortion(units: Decimal, kind: HeaderPump) -> Double {
        let units = NSDecimalNumber(decimal: units).doubleValue
        let filled = kind == .pod || kind == .medtrum ? (units + 10) * 1.2 / 200 : units / 300
        return 1 - min(max(filled, 0), 1)
    }

    /// The reservoir is drawn in orange below this many units.
    static let lowReservoirUnits: Decimal = 15

    /// SF Symbols has "battery.25", ".50", ".75" and ".100".
    static func batterySymbolLevel(percent: Int) -> Int {
        percent > 80 ? 100 : percent > 60 ? 75 : percent > 40 ? 50 : 25
    }

    private var insulinConcentration: Double {
        concentration.last?.concentration ?? 1
    }

    var body: some View {
        let element = Self.element(info: appUIState.pumpInfo, status: appUIState.pumpStatus, now: timerDate)
        let patch = element.device?.kind == .medtrum
        HStack(spacing: 5) {
            switch element {
            case .noPump:
                label("No Pump")
            case .reconnect:
                label("Re-connect pump!", color: .red)
            case .noPod:
                label("No Pod")
            case .noPatch:
                label("No Patch")
            case let .device(device):
                deviceView(device)
            }
        }
        .offset(x: patch ? 5 : 0, y: patch ? 10 : 5)
    }

    private func label(_ key: LocalizedStringKey, color: Color = .secondary) -> some View {
        Text(key).font(.statusFont).foregroundStyle(color)
            .offset(y: -4)
    }

    /// Left to right: the reservoir's units, the device's icon with its badges, the pod's / patch's remaining time,
    /// the battery.
    @ViewBuilder private func deviceView(_ device: Device) -> some View {
        let wearable = device.kind == .pod || device.kind == .medtrum
        let showsInsulinBadge = insulinConcentration != 1 && !hideInsulinBadge

        if showsInsulinBadge, !wearable {
            NonStandardInsulin(concentration: insulinConcentration, pump: device.kind)
        }

        switch device.reservoir {
        case let .some(.units(units)):
            reservoirText(units, wearable: wearable)
        case .some(.aboveThreshold):
            EmptyView()
        case .none:
            // a pod or a patch has its remaining time to show
            if !wearable { label("---") }
        }

        deviceIcon(device)
            .padding(.leading, insulinConcentration != 1 ? 7 : 0)
            .overlay {
                if device.clockOffset {
                    ClockOffset(mdtPump: !wearable)
                }
                if showsInsulinBadge, wearable {
                    NonStandardInsulin(concentration: insulinConcentration, pump: device.kind)
                }
            }

        if let lifetime = device.lifetime {
            remainingTime(lifetime)
                .font(.pumpFont)
                .offset(x: device.kind == .medtrum ? -8.5 : -5)
        }

        if let percent = device.batteryPercent {
            Image(systemName: "battery.\(Self.batterySymbolLevel(percent: percent))")
                .resizable()
                .rotationEffect(.degrees(-90))
                .frame(maxWidth: 32, maxHeight: 12)
                .foregroundColor(batteryColor(percent))
                .offset(x: -5, y: -0.9)
                .padding(.bottom, 2)
        }
    }

    private func reservoirText(_ units: Decimal, wearable: Bool) -> some View {
        HStack(spacing: 0) {
            let amount: Decimal = units * Decimal(insulinConcentration)
            Text(reservoirFormatter.string(from: amount as NSNumber) ?? "")
                .padding(.trailing, wearable ? 2 : 0)
            Text("U").foregroundStyle(.secondary)
        }
        .font(wearable ? nil : .statusFont)
        .offset(x: wearable ? 6 : 0, y: wearable ? 0 : 7)
    }

    /// The device's picture, filled to the reservoir's level (none while the level is not known), dimmed under a
    /// badge when the pump does not deliver as it should.
    private func deviceIcon(_ device: Device) -> some View {
        ZStack {
            if let reservoir = device.reservoir {
                let portion: Double = reservoir.knownValue.map { Self.emptyPortion(units: $0, kind: device.kind) } ?? 0
                let low = reservoir.knownValue.map { $0 < Self.lowReservoirUnits } ?? false
                Group {
                    switch device.kind {
                    case .pod: podInsulinAmount(portion: portion, low: low)
                    case .medtrum: medtrumInsulinAmount(portion: portion, low: low)
                    default: pumpInsulinAmount(portion: portion, low: low)
                    }
                }
                .opacity(device.state == .normal ? 1 : 0.35)
            }
            stateBadge(device.state)
                .offset(y: device.reservoir == nil ? 0 : -4)
        }
    }

    @ViewBuilder private func stateBadge(_ state: DeviceState) -> some View {
        switch state {
        case .normal:
            EmptyView()
        case .suspended:
            badge("pause.circle.fill", color: .orange)
        case .deliveryUncertain:
            badge("questionmark.circle.fill", color: .orange)
        case .critical:
            badge("exclamationmark.triangle.fill", color: .red)
        }
    }

    private func badge(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
    }

    private func remainingTime(_ lifetime: Lifetime) -> some View {
        HStack {
            switch lifetime {
            case let .remaining(time):
                durationLabel(time, prefix: " ", unitColor: time < 4 * 60 * 60 ? .red : .secondary)
            case let .expired(time):
                // Expired: show how far into the grace period the pod is, under "Replace".
                VStack(spacing: 0) {
                    Text(NSLocalizedString("Replace", comment: "View/Header when pod expired"))
                    durationLabel(time, prefix: "-", unitColor: .red, minutesUnderADay: true)
                        .font(.caption2)
                }
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }

    /// "2d 5h", "17h" (or "17h 23m" with `minutesUnderADay`) and "42m" for a non-negative interval,
    /// with `prefix` in front of the first number.
    @ViewBuilder private func durationLabel(
        _ interval: TimeInterval,
        prefix: String,
        unitColor: Color,
        minutesUnderADay: Bool = false
    ) -> some View {
        let totalMinutes = Int(interval / TimeInterval.minutes(1))
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes / 60 % 24
        let minutes = totalMinutes % 60
        HStack(spacing: 0) {
            if days >= 1 {
                Text("\(prefix)\(days)")
                Text(NSLocalizedString("d", comment: "abbreviation for days")).foregroundStyle(unitColor)
                Text(" \(hours)")
                Text(NSLocalizedString("h", comment: "abbreviation for hours")).foregroundStyle(unitColor)
            } else if hours >= 1 {
                Text("\(prefix)\(hours)")
                Text(NSLocalizedString("h", comment: "abbreviation for hours")).foregroundStyle(unitColor)
                if minutesUnderADay {
                    Text(" \(minutes)")
                    Text(NSLocalizedString("m", comment: "abbreviation for minutes")).foregroundStyle(unitColor)
                }
            } else {
                Text("\(prefix)\(minutes)")
                Text(NSLocalizedString("m", comment: "abbreviation for minutes")).foregroundStyle(unitColor)
            }
        }
    }

    private func batteryColor(_ percent: Int) -> Color {
        switch percent {
        case ...10:
            return .red
        case ...20:
            return .yellow
        default:
            return .green
        }
    }

    private func podInsulinAmount(portion: Double, low: Bool) -> some View {
        ZStack {
            let pump = colorScheme == .dark ? "pod_dark" : "pod_light"
            filledPumpImage(named: pump, color: insulinColour(low: low).opacity(0.8), portion: portion)
                .resizable()
                .aspectRatio(0.72, contentMode: .fit)
                .frame(width: IAPSconfig.iconSize, height: IAPSconfig.iconSize)
                .symbolRenderingMode(.palette)
                .offset(x: 0, y: -5)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .overlay {
                    let units = 50 * (concentration.last?.concentration ?? 1)
                    portion <= 0.3 ?
                        Text((reservoirFormatter.string(from: units as NSNumber) ?? "") + "+").foregroundStyle(.white)
                        .font(.system(size: 6))
                        .offset(y: -4)
                        : nil
                }
        }
    }

    private func pumpInsulinAmount(portion: Double, low: Bool) -> some View {
        ZStack {
            let pump = colorScheme == .dark ? "pump_dark" : "pump_light"
            filledPumpImage(named: pump, color: insulinColour(low: low).opacity(0.8), portion: max(portion, 0.3))
                .resizable()
                .frame(maxWidth: 17, maxHeight: 36)
                .symbolRenderingMode(.palette)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .padding(.bottom, 5)
        }
    }

    private func medtrumInsulinAmount(portion: Double, low: Bool) -> some View {
        ZStack {
            filledPumpImage(named: "nano", color: insulinColour(low: low).opacity(0.8), portion: max(portion, 0.3))
                .resizable()
                .aspectRatio(0.7, contentMode: .fit)
                .frame(height: IAPSconfig.iconSize)
                .symbolRenderingMode(.palette)
                .shadow(radius: 1, x: 2, y: 2)
                .foregroundStyle(.white)
                .padding(5)
                .offset(y: -5)
        }
    }

    private func insulinColour(low: Bool) -> Color {
        low ? Color.orange : Color.insulin
    }
}

private extension PumpView.Element {
    var device: PumpView.Device? {
        if case let .device(device) = self { return device }
        return nil
    }
}
