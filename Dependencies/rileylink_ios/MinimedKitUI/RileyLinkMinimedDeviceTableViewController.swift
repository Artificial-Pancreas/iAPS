//
//  RileyLinkMinimedDeviceTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import CoreBluetooth
import LoopKitUI
import MinimedKit
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI

let CellIdentifier = "Cell"

public class RileyLinkMinimedDeviceTableViewController: UITableViewController {

    public let device: RileyLinkDevice

    private let ops: PumpOps

    private var pumpState: PumpState? {
        didSet {
            // Update the UI if its visible
            guard rssiFetchTimer != nil else { return }

            if let cell = cellForRow(.awake) {
                cell.setAwakeUntil(pumpState?.awakeUntil, formatter: dateFormatter)
            }

            if let cell = cellForRow(.model) {
                cell.setPumpModel(pumpState?.pumpModel)
            }
            
            if let cell = cellForRow(.tune) {
                cell.setTuneInfo(lastValidFrequency: pumpState?.lastValidFrequency, lastTuned: pumpState?.lastTuned, measurementFormatter: measurementFormatter, dateFormatter: dateFormatter)
            }
        }
    }

    private var bleRSSI: Int?

    private var firmwareVersion: String? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.version)?.detailTextLabel?.text = firmwareVersion
        }
    }
    
    private var fw_hw: String? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.orl)?.detailTextLabel?.text = fw_hw
        }
    }
    
    private var disconnectLed: Bool = false
    private var disconnectVibration: Bool = false
    
    private var connectLed: Bool = false
    private var connectVibration: Bool = false
    
    private var uptime: TimeInterval? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.uptime)?.setDetailAge(uptime)
        }
    }
    
    private var battery: String? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.battery)?.setDetailBatteryLevel(battery)
        }
    }


    private var lastIdle: Date? {
        didSet {
            guard isViewLoaded else {
                return
            }

            cellForRow(.idleStatus)?.setDetailDate(lastIdle, formatter: dateFormatter)
        }
    }
    
    private var rssiFetchTimer: Timer? {
        willSet {
            rssiFetchTimer?.invalidate()
        }
    }

    private var appeared = false

    public init(device: RileyLinkDevice, pumpOps: PumpOps) {
        self.device = device
        self.ops = pumpOps
        self.pumpState = pumpOps.pumpState.value

        super.init(style: .grouped)

        updateDeviceStatus()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = device.name

        self.observe()
    }
    
    @objc func updateRSSI() {
        device.readRSSI()
    }
    
    func updateUptime() {
        device.runSession(withName: "Get stats for uptime") { (session) in
            do {
                let statistics = try session.getRileyLinkStatistics()
                DispatchQueue.main.async {
                    self.uptime = statistics.uptime
                }
            } catch { }
        }
    }
    
    func updateBatteryLevel() {
        device.runSession(withName: "Get battery level") { (session) in
            let batteryLevel = self.device.getBatterylevel()
            DispatchQueue.main.async {
                self.battery = batteryLevel
            }
        }
    }
    
    func orangeClose() {
        device.runSession(withName: "Orange Action Close") { (session) in
            self.device.orangeClose()
        }
    }
    
    func orangeReadSet() {
        device.runSession(withName: "orange Read Set") { (session) in
            self.device.orangeReadSet()
        }
    }

    func writePSW() {
        device.runSession(withName: "Orange Action PSW") { (session) in
            self.device.orangeWritePwd()
        }
    }
    
    func orangeAction(index: Int) {
        device.runSession(withName: "Orange Action \(index)") { (session) in
            self.device.orangeAction(mode: index)
        }
    }
    
    func orangeAction(index: Int, open: Bool) {
        device.runSession(withName: "Orange Set Action \(index)") { (session) in
            self.device.orangeSetAction(index: index, open: open)
        }
    }
    
    private func updateDeviceStatus() {
        device.getStatus { (status) in
            DispatchQueue.main.async {
                self.firmwareVersion = status.firmwareDescription
                self.fw_hw = status.fw_hw
                self.connectLed = status.ledOn
                self.connectVibration = status.vibrationOn
                self.disconnectLed = status.ledOn
                self.disconnectVibration = status.vibrationOn
                
                self.tableView.reloadData()
            }
        }
    }

    // References to registered notification center observers
    private var notificationObservers: [Any] = []
    
    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        let mainQueue = OperationQueue.main
        
        notificationObservers = [
            center.addObserver(forName: .DeviceNameDidChange, object: device, queue: mainQueue) { [weak self] (note) -> Void in
                if let cell = self?.cellForRow(.customName) {
                    cell.detailTextLabel?.text = self?.device.name
                }

                self?.title = self?.device.name
            },
            center.addObserver(forName: .DeviceConnectionStateDidChange, object: device, queue: mainQueue) { [weak self] (note) -> Void in
                if let cell = self?.cellForRow(.connection) {
                    cell.detailTextLabel?.text = self?.device.peripheralState.description
                }
            },
            center.addObserver(forName: .DeviceRSSIDidChange, object: device, queue: mainQueue) { [weak self] (note) -> Void in
                self?.bleRSSI = note.userInfo?[RileyLinkDevice.notificationRSSIKey] as? Int

                if let cell = self?.cellForRow(.rssi), let formatter = self?.integerFormatter {
                    cell.setDetailRSSI(self?.bleRSSI, formatter: formatter)
                }
            },
            center.addObserver(forName: .DeviceDidStartIdle, object: device, queue: mainQueue) { [weak self] (note) in
                self?.updateDeviceStatus()
            },
            center.addObserver(forName: .PumpOpsStateDidChange, object: ops, queue: mainQueue) { [weak self] (note) in
                if let state = note.userInfo?[PumpOps.notificationPumpStateKey] as? PumpState {
                    self?.pumpState = state
                }
            },
            center.addObserver(forName: .DeviceFW_HWChange, object: device, queue: mainQueue) { [weak self] (note) in
                self?.updateDeviceStatus()
            },
        ]
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if appeared {
            tableView.reloadData()
        }
        
        rssiFetchTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(updateRSSI), userInfo: nil, repeats: true)
        
        appeared = true
        
        updateRSSI()
        
        updateUptime()
        
        updateBatteryLevel()
        
        writePSW()
        
        orangeAction(index: 9)
        
        orangeReadSet()
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        orangeClose()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        rssiFetchTimer = nil
    }


    // MARK: - Formatters

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()

        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .medium

        return dateFormatter
    }()
    
    private lazy var integerFormatter = NumberFormatter()

    private lazy var measurementFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()

        formatter.numberFormatter = decimalFormatter

        return formatter
    }()

    private lazy var decimalFormatter: NumberFormatter = {
        let decimalFormatter = NumberFormatter()

        decimalFormatter.numberStyle = .decimal
        decimalFormatter.minimumSignificantDigits = 5

        return decimalFormatter
    }()

    // MARK: - Table view data source

    private enum Section: Int, CaseCountable {
        case device
        case pump
        case commands
    }

    private enum DeviceRow: Int, CaseCountable {
        case customName
        case version
        case rssi
        case connection
        case uptime
        case idleStatus
        case battery
        case orl
    }

    private enum PumpRow: Int, CaseCountable {
        case id
        case model
        case awake
    }

    private enum CommandRow: Int, CaseCountable {
        case tune
        case changeTime
        case mySentryPair
        case dumpHistory
        case fetchGlucose
        case getPumpModel
        case pressDownButton
        case readPumpStatus
        case readBasalSchedule
        case enableLED
        case discoverCommands
        case getStatistics
        case yellow
        case red
        case off
        case shake
        case shakeOff
        case disconnectLed
        case disconnectVibration
        case connectLed
        case connectVibration
    }

    @objc
    func switchAction(sender: RileyLinkSwitch) {
        switch CommandRow(rawValue: sender.index)! {
        case .connectLed:
            orangeAction(index: 4, open: sender.isOn)
        case .connectVibration:
            orangeAction(index: 5, open: sender.isOn)
        case .disconnectLed:
            orangeAction(index: 2, open: sender.isOn)
        case .disconnectVibration:
            orangeAction(index: 3, open: sender.isOn)
        default:
            break
        }
    }
    
    private func cellForRow(_ row: DeviceRow) -> UITableViewCell? {
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: Section.device.rawValue))
    }

    private func cellForRow(_ row: PumpRow) -> UITableViewCell? {
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: Section.pump.rawValue))
    }

    private func cellForRow(_ row: CommandRow) -> UITableViewCell? {
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: Section.commands.rawValue))
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .device:
            return DeviceRow.count
        case .pump:
            return PumpRow.count
        case .commands:
            return CommandRow.count
        }
    }
    
    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 45
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        if let reusableCell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier) {
            cell = reusableCell
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: CellIdentifier)
            let switchView = RileyLinkSwitch()
            switchView.tag = 10000
            switchView.addTarget(self, action: #selector(switchAction(sender:)), for: .valueChanged)
            switchView.frame = CGRect(x: tableView.frame.width - 51 - 20, y: 7, width: 51, height: 31)
            cell.contentView.addSubview(switchView)
        }
        
        let switchView = cell.contentView.viewWithTag(10000) as? RileyLinkSwitch
        switchView?.isHidden = true
        switchView?.index = indexPath.row
        
        cell.accessoryType = .none

        switch Section(rawValue: indexPath.section)! {
        case .device:
            switch DeviceRow(rawValue: indexPath.row)! {
            case .customName:
                cell.textLabel?.text = LocalizedString("Name", comment: "The title of the cell showing device name")
                cell.detailTextLabel?.text = device.name
                cell.accessoryType = .disclosureIndicator
            case .version:
                cell.textLabel?.text = LocalizedString("Firmware", comment: "The title of the cell showing firmware version")
                cell.detailTextLabel?.text = firmwareVersion
            case .connection:
                cell.textLabel?.text = LocalizedString("Connection State", comment: "The title of the cell showing BLE connection state")
                cell.detailTextLabel?.text = device.peripheralState.description
            case .rssi:
                cell.textLabel?.text = LocalizedString("Signal Strength", comment: "The title of the cell showing BLE signal strength (RSSI)")
                cell.setDetailRSSI(bleRSSI, formatter: integerFormatter)
            case .uptime:
                cell.textLabel?.text = LocalizedString("Uptime", comment: "The title of the cell showing uptime")
                cell.setDetailAge(uptime)
            case .idleStatus:
                cell.textLabel?.text = LocalizedString("On Idle", comment: "The title of the cell showing the last idle")
                cell.setDetailDate(lastIdle, formatter: dateFormatter)
            case .battery:
                cell.textLabel?.text = NSLocalizedString("Battery Level", comment: "The title of the cell showing battery level")
                cell.setDetailBatteryLevel(battery)
            case .orl:
                cell.textLabel?.text = NSLocalizedString("ORL", comment: "The title of the cell showing ORL")
                cell.detailTextLabel?.text = fw_hw
            }
        case .pump:
            switch PumpRow(rawValue: indexPath.row)! {
            case .id:
                cell.textLabel?.text = LocalizedString("Pump ID", comment: "The title of the cell showing pump ID")
                cell.detailTextLabel?.text = ops.pumpSettings.pumpID
            case .model:
                cell.textLabel?.text = LocalizedString("Pump Model", comment: "The title of the cell showing the pump model number")
                cell.setPumpModel(pumpState?.pumpModel)
            case .awake:
                cell.setAwakeUntil(pumpState?.awakeUntil, formatter: dateFormatter)
            }
        case .commands:
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil

            switch CommandRow(rawValue: indexPath.row)! {
            case .tune:
                cell.setTuneInfo(lastValidFrequency: pumpState?.lastValidFrequency, lastTuned: pumpState?.lastTuned, measurementFormatter: measurementFormatter, dateFormatter: dateFormatter)
            case .changeTime:
                cell.textLabel?.text = LocalizedString("Change Time", comment: "The title of the command to change pump time")

                let localTimeZone = TimeZone.current
                let localTimeZoneName = localTimeZone.abbreviation() ?? localTimeZone.identifier

                if let pumpTimeZone = pumpState?.timeZone {
                    let timeZoneDiff = TimeInterval(pumpTimeZone.secondsFromGMT() - localTimeZone.secondsFromGMT())
                    let formatter = DateComponentsFormatter()
                    formatter.allowedUnits = [.hour, .minute]
                    let diffString = timeZoneDiff != 0 ? formatter.string(from: abs(timeZoneDiff)) ?? String(abs(timeZoneDiff)) : ""

                    cell.detailTextLabel?.text = String(format: LocalizedString("%1$@%2$@%3$@", comment: "The format string for displaying an offset from a time zone: (1: GMT)(2: -)(3: 4:00)"), localTimeZoneName, timeZoneDiff != 0 ? (timeZoneDiff < 0 ? "-" : "+") : "", diffString)
                } else {
                    cell.detailTextLabel?.text = localTimeZoneName
                }
            case .mySentryPair:
                cell.textLabel?.text = LocalizedString("MySentry Pair", comment: "The title of the command to pair with mysentry")

            case .dumpHistory:
                cell.textLabel?.text = LocalizedString("Fetch Recent History", comment: "The title of the command to fetch recent history")

            case .fetchGlucose:
                cell.textLabel?.text = LocalizedString("Fetch Enlite Glucose", comment: "The title of the command to fetch recent glucose")
                
            case .getPumpModel:
                cell.textLabel?.text = LocalizedString("Get Pump Model", comment: "The title of the command to get pump model")

            case .pressDownButton:
                cell.textLabel?.text = LocalizedString("Send Button Press", comment: "The title of the command to send a button press")

            case .readPumpStatus:
                cell.textLabel?.text = LocalizedString("Read Pump Status", comment: "The title of the command to read pump status")

            case .readBasalSchedule:
                cell.textLabel?.text = LocalizedString("Read Basal Schedule", comment: "The title of the command to read basal schedule")
            
            case .enableLED:
                cell.textLabel?.text = LocalizedString("Enable Diagnostic LEDs", comment: "The title of the command to enable diagnostic LEDs")

            case .discoverCommands:
                cell.textLabel?.text = LocalizedString("Discover Commands", comment: "The title of the command to discover commands")
                
            case .getStatistics:
                cell.textLabel?.text = LocalizedString("RileyLink Statistics", comment: "The title of the command to fetch RileyLink statistics")
            case .yellow:
                cell.textLabel?.text = NSLocalizedString("Lighten Yellow LED", comment: "The title of the cell showing Lighten Yellow LED")
            case .red:
                cell.textLabel?.text = NSLocalizedString("Lighten Red LED", comment: "The title of the cell showing Lighten Red LED")
            case .off:
                cell.textLabel?.text = NSLocalizedString("Turn Off LED", comment: "The title of the cell showing Turn Off LED")
            case .shake:
                cell.textLabel?.text = NSLocalizedString("Test Vibrator", comment: "The title of the cell showing Test Vibrator")
            case .shakeOff:
                cell.textLabel?.text = NSLocalizedString("Stop Vibrator", comment: "The title of the cell showing Stop Vibrator")
            case .disconnectLed:
                switchView?.isHidden = false
                switchView?.isOn = disconnectLed
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Disconnect Led", comment: "The title of the cell showing Stop Vibrator")
            case .disconnectVibration:
                switchView?.isHidden = false
                switchView?.isOn = disconnectVibration
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Disconnect Vibrator", comment: "The title of the cell showing Stop Vibrator")
            case .connectLed:
                switchView?.isHidden = false
                switchView?.isOn = connectLed
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Connect Led", comment: "The title of the cell showing Stop Vibrator")
            case .connectVibration:
                switchView?.isHidden = false
                switchView?.isOn = connectVibration
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Connect Vibrator", comment: "The title of the cell showing Stop Vibrator")
            }
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .device:
            return LocalizedString("Device", comment: "The title of the section describing the device")
        case .pump:
            return LocalizedString("Pump", comment: "The title of the section describing the pump")
        case .commands:
            return LocalizedString("Commands", comment: "The title of the section describing commands")
        }
    }

    // MARK: - UITableViewDelegate

    public override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section)! {
        case .device:
            switch DeviceRow(rawValue: indexPath.row)! {
            case .customName:
                return true
            default:
                return false
            }
        case .pump:
            return false
        case .commands:
            return device.peripheralState == .connected
        }
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .device:
            switch DeviceRow(rawValue: indexPath.row)! {
            case .customName:
                let vc = TextFieldTableViewController()
                if let cell = tableView.cellForRow(at: indexPath) {
                    vc.title = cell.textLabel?.text
                    vc.value = device.name
                    vc.delegate = self
                    vc.keyboardType = .default
                }

                show(vc, sender: indexPath)
            default:
                break
            }
        case .commands:
            var vc: CommandResponseViewController?

            switch CommandRow(rawValue: indexPath.row)! {
            case .tune:
                vc = .tuneRadio(ops: ops, device: device, measurementFormatter: measurementFormatter)
            case .changeTime:
                vc = .changeTime(ops: ops, device: device)
            case .mySentryPair:
                vc = .mySentryPair(ops: ops, device: device)
            case .dumpHistory:
                vc = .dumpHistory(ops: ops, device: device)
            case .fetchGlucose:
                vc = .fetchGlucose(ops: ops, device: device)
            case .getPumpModel:
                vc = .getPumpModel(ops: ops, device: device)
            case .pressDownButton:
                vc = .pressDownButton(ops: ops, device: device)
            case .readPumpStatus:
                vc = .readPumpStatus(ops: ops, device: device, measurementFormatter: measurementFormatter)
            case .readBasalSchedule:
                vc = .readBasalSchedule(ops: ops, device: device, integerFormatter: integerFormatter)
            case .enableLED:
                vc = .enableLEDs(ops: ops, device: device)
            case .discoverCommands:
                vc = .discoverCommands(ops: ops, device: device)
            case .getStatistics:
                vc = .getStatistics(ops: ops, device: device)
            case .yellow: orangeAction(index: 1)
            case .red: orangeAction(index: 2)
            case .off: orangeAction(index: 3)
            case .shake: orangeAction(index: 4)
            case .shakeOff: orangeAction(index: 5)
            default:
                break
            }

            if let cell = tableView.cellForRow(at: indexPath) {
                vc?.title = cell.textLabel?.text
            }

            if let vc = vc {
                show(vc, sender: indexPath)
            }
        case .pump:
            break
        }
    }
}


extension RileyLinkMinimedDeviceTableViewController: TextFieldTableViewControllerDelegate {
    public func textFieldTableViewControllerDidReturn(_ controller: TextFieldTableViewController) {
        _ = navigationController?.popViewController(animated: true)
    }

    public func textFieldTableViewControllerDidEndEditing(_ controller: TextFieldTableViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .device:
                switch DeviceRow(rawValue: indexPath.row)! {
                case .customName:
                    device.setCustomName(controller.value!)
                default:
                    break
                }
            default:
                break

            }
        }
    }
}

private extension TimeInterval {
    func format(using units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: self)
    }
}


private extension UITableViewCell {
    
    func setDetailBatteryLevel(_ batteryLevel: String?) {
        if let unwrappedBatteryLevel = batteryLevel {
            detailTextLabel?.text = unwrappedBatteryLevel + " %"
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    
    func setDetailDate(_ date: Date?, formatter: DateFormatter) {
        if let date = date {
            detailTextLabel?.text = formatter.string(from: date)
        } else {
            detailTextLabel?.text = "-"
        }
    }

    func setDetailRSSI(_ decibles: Int?, formatter: NumberFormatter) {
        detailTextLabel?.text = formatter.decibleString(from: decibles) ?? "-"
    }

    func setDetailAge(_ age: TimeInterval?) {
        if let age = age {
            detailTextLabel?.text = age.format(using: [.day, .hour, .minute])
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setAwakeUntil(_ awakeUntil: Date?, formatter: DateFormatter) {
        switch awakeUntil {
        case let until? where until.timeIntervalSinceNow < 0:
            textLabel?.text = LocalizedString("Last Awake", comment: "The title of the cell describing an awake radio")
            setDetailDate(until, formatter: formatter)
        case let until?:
            textLabel?.text = LocalizedString("Awake Until", comment: "The title of the cell describing an awake radio")
            setDetailDate(until, formatter: formatter)
        default:
            textLabel?.text = LocalizedString("Listening Off", comment: "The title of the cell describing no radio awake data")
            detailTextLabel?.text = nil
        }
    }

    func setPumpModel(_ pumpModel: PumpModel?) {
        if let pumpModel = pumpModel {
            detailTextLabel?.text = String(describing: pumpModel)
        } else {
            detailTextLabel?.text = LocalizedString("Unknown", comment: "The detail text for an unknown pump model")
        }
    }
    
    func setTuneInfo(lastValidFrequency: Measurement<UnitFrequency>?, lastTuned: Date?, measurementFormatter: MeasurementFormatter, dateFormatter: DateFormatter) {
        if let frequency = lastValidFrequency, let date = lastTuned {
            textLabel?.text = measurementFormatter.string(from: frequency)
            setDetailDate(date, formatter: dateFormatter)
        } else {
            textLabel?.text = LocalizedString("Tune Radio Frequency", comment: "The title of the command to re-tune the radio")
        }
    }

}
