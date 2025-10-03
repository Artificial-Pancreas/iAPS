import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

internal class MedtrumKitHUDProvider: NSObject, HUDProvider {
    private let processQueue = DispatchQueue(label: "com.nightscout.medtrumkit.hudProvider")
    private let pumpManager: MedtrumPumpManager

    private let bluetoothProvider: BluetoothProvider

    private let colorPalette: LoopUIColorPalette

    private let allowedInsulinTypes: [InsulinType]
    private var reservoirView: MedtrumReservoirView?

    var visible: Bool = true

    public init(
        pumpManager: MedtrumPumpManager,
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowedInsulinTypes: [InsulinType]
    ) {
        self.pumpManager = pumpManager
        self.bluetoothProvider = bluetoothProvider
        self.colorPalette = colorPalette
        self.allowedInsulinTypes = allowedInsulinTypes
        super.init()

        self.pumpManager.addStatusObserver(self, queue: processQueue)
    }

    public func createHUDView() -> BaseHUDView? {
        reservoirView = MedtrumReservoirView.instantiate()
        updateReservoirView()

        return reservoirView
    }

    func didTapOnHUDView(_: LoopKitUI.BaseHUDView, allowDebugFeatures _: Bool) -> LoopKitUI.HUDTapAction? {
        nil
    }

    var hudViewRawState: HUDViewRawState {
        var rawValue: HUDProvider.HUDViewRawState = [:]

        rawValue["lastSync"] = pumpManager.state.lastSync
        rawValue["reservoir"] = pumpManager.state.reservoir
        rawValue["maxReservoir"] = pumpManager.state.pumpName.contains("300u") ? 300 : 200
        return rawValue
    }

    var managerIdentifier: String {
        pumpManager.managerIdentifier
    }

    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        let reservoirView: MedtrumReservoirView?

        if let lastStatusDate = rawValue["lastSync"] as? Date,
           let reservoir = rawValue["reservoir"] as? Double,
           let maxReservoir = rawValue["maxReservoir"] as? Double
        {
            reservoirView = MedtrumReservoirView.instantiate()
            reservoirView!.update(level: reservoir, at: lastStatusDate, max: maxReservoir)
        } else {
            reservoirView = nil
        }

        return reservoirView
    }

    private func updateReservoirView() {
        guard let reservoirView = reservoirView else {
            return
        }

        reservoirView.update(
            level: pumpManager.state.reservoir,
            at: pumpManager.state.lastSync,
            max: pumpManager.state.pumpName.contains("300u") ? 300 : 200
        )
    }
}

extension MedtrumKitHUDProvider: PumpManagerStatusObserver {
    func pumpManager(_: any LoopKit.PumpManager, didUpdate _: LoopKit.PumpManagerStatus, oldStatus _: LoopKit.PumpManagerStatus) {
        updateReservoirView()
    }
}
