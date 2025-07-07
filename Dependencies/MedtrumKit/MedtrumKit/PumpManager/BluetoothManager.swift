import CoreBluetooth

class BluetoothManager: NSObject, CBCentralManagerDelegate {
    public var pumpManager: MedtrumPumpManager?

    let log = MedtrumLogger(category: "BluetoothManager")

    var manager: CBCentralManager!
    let managerQueue = DispatchQueue(label: "com.nightscout.MedtrumKit.bluetoothManagerQueue", qos: .unspecified)

    private var peripheral: CBPeripheral?
    private var peripheralManager: PeripheralManager?

    var scanCompletion: ((MedtrumScanResult) -> Void)?
    var connectCompletion: ((MedtrumConnectError?) -> Void)?

    public var isConnected: Bool {
        if let peripheral = peripheral, peripheral.state == .connected {
            return true
        }

        return false
    }

    override init() {
        super.init()

        managerQueue.sync {
            self.manager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "com.nightscout.MedtrumKit.bluetoothManager"]
            )
        }
    }

    func startScan(_ completion: @escaping (_ result: MedtrumScanResult) -> Void) {
        if let pumpManager = self.pumpManager, pumpManager.state.pumpSN.isEmpty {
            completion(.failure(error: .noSerialNumberAvailable))
            return
        }
        guard manager.state == .poweredOn else {
            completion(.failure(error: .invalidBluetoothState(state: manager.state)))
            return
        }

        if !manager.isScanning {
            manager.stopScan()
        }

        scanCompletion = completion
        manager.scanForPeripherals(withServices: [])

        log.info("Started scanning")
        // TODO: Add scan timeout - 15s?
    }

    private func connect(peripheral: CBPeripheral) {
        if manager.isScanning {
            manager.stopScan()
            scanCompletion = nil
        }

        log.info("Connecting to \(peripheral)")

        self.peripheral = peripheral
        manager.connect(peripheral)
    }

    func ensureConnected(autoDisconnect: Bool = true, _ completionAsync: @escaping (MedtrumConnectError?) async -> Void) {
        let completion = { (_ result: MedtrumConnectError?) -> Void in
            Task {
                await completionAsync(result)
                if autoDisconnect {
                    self.disconnect()
                }

                self.connectCompletion = nil
            }
        }
        connectCompletion = completion

        if let peripheral = peripheral, peripheral.state == .connected {
            // We are connected and ready to continue
            completion(nil)
            return
        }

        if let peripheral = peripheral {
            // We've the peripheral reference to a previous connection
            // Just try to reconnect
            startTimeout(seconds: .seconds(15))
            connect(peripheral: peripheral)
            return
        }

        let connectedDevices = manager.retrieveConnectedPeripherals(withServices: [PeripheralManager.SERVICE_UUID])
        if let peripheral = connectedDevices.first(where: { $0.name == "MT" }) {
            // Phone is already connected, but the app is not
            connect(peripheral: peripheral)
            return
        }

        guard var pumpSNState = pumpManager?.state.pumpSN else {
            log.error("No pump serial number found")
            completion(.failedToFindDevice)
            return
        }

        pumpSNState = Data(pumpSNState.reversed())

        // We are disconnected and have no reference to the previous connection
        // Start to scan for patch and reconnect the long way
        startScan { result in
            switch result {
            case let .failure(error):
                self.log.error("Error during scanning: \(error.localizedDescription)")
                self.manager.stopScan()
                completion(.failedToFindDevice)

            case let .success(peripheral, pumpSN, _, _):
                guard pumpSN == pumpSNState else {
                    // Other patch pump found. IGNORE
                    return
                }

                self.connect(peripheral: peripheral)
            }
        }
    }

    func startTimeout(seconds: TimeInterval) {
        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard let connectionCallback = self.connectCompletion else {
                    // This is amazing, we've done what we must and continue our live :)
                    return
                }

                self.log.error("Failed to connect: Timeout reached...")

                connectionCallback(.failedToConnectToDevice)
                self.connectCompletion = nil
            } catch {}
        }
    }

    func write(_ packet: any MedtrumBasePacketProtocol) async -> MedtrumWriteResult<Any> {
        guard let peripheralManager else {
            return .failure(error: .noManager)
        }

        return await peripheralManager.writePacket(packet)
    }

    func disconnect() {
        if let pumpManager = self.pumpManager, pumpManager.state.usingHeartbeatMode {
            // We are using heartbeat mode, so prevent disconnect
            return
        }

        if let peripheral = self.peripheral, peripheral.state == .connected {
            manager.cancelPeripheralConnection(peripheral)
        }
    }
}

extension BluetoothManager {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("\(String(describing: central.state.rawValue))")

        if central.state == .poweredOn, !isConnected, pumpManager?.state.pumpState == .active {
            ensureConnected { error in
                if let error = error {
                    self.log.error("Failed to auto reconnect on boot: \(error)")
                }
            }
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        guard let deviceName = peripheral.name, !deviceName.isEmpty else {
            return
        }

        guard deviceName == "MT" else {
            return
        }

        let manufacturerData = advertisementData["kCBAdvDataManufacturerData"]
        guard let manufacturerData = manufacturerData as? Data, manufacturerData.count >= 7 else {
            log.warning("No ManufacturerData or too short - " + advertisementData.keys.joined(separator: ", "))
            return
        }

        // Index:
        // 0 & 1 -> Manufacturer ID
        // 2-5 -> PumpSN
        // 6 -> Device type
        // 7 -> Version
        scanCompletion?(
            .success(
                peripheral: peripheral,
                pumpSN: manufacturerData[2 ..< 6],
                deviceType: manufacturerData[6],
                version: manufacturerData[7]
            )
        )
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("Connected to pump: \(peripheral.name ?? "<NO_NAME>")!")

        guard let completion = connectCompletion, let pumpManager = pumpManager else {
            return
        }

        self.peripheral = peripheral
        peripheralManager = PeripheralManager(peripheral, self, pumpManager, completion)
        peripheral.discoverServices([PeripheralManager.SERVICE_UUID])
    }

    func centralManager(_: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict["CBCentralManagerRestoredCentrals"] as? [CBPeripheral] ?? []
        guard !peripherals.isEmpty, let peripheral = peripherals.first else {
            log.warning("No restored peripherals!")
            return
        }

        guard let pumpManager = pumpManager else {
            log.warning("Couldnt restore state, since no pumpManager is available...")
            return
        }

        self.peripheral = peripheral
        peripheralManager = PeripheralManager(peripheral, self, pumpManager) { reconnectResult in
            if let error = reconnectResult {
                self.log.warning("Couldnt reconnect to pump: \(error)")
                return
            }

            self.log.info("Reconnected to patch using restored state!")
        }

        peripheral.discoverServices([PeripheralManager.SERVICE_UUID])
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: Error?) {
        log.info("Device disconnected, name: \(peripheral.name ?? "<NO_NAME>")")

        if let pumpManager = self.pumpManager {
            pumpManager.state.isConnected = false
            pumpManager.notifyStateDidChange()
        }

        if peripheralManager != nil {
            peripheralManager = nil
        }
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.info("Device connect error, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error!.localizedDescription)")

        guard let pumpManager = self.pumpManager else {
            return
        }

        pumpManager.state.isConnected = false
        pumpManager.notifyStateDidChange()
    }
}
