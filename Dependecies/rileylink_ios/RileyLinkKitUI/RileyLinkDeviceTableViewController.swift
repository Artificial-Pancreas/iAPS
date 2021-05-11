//
//  RileyLinkDeviceTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKitUI
import RileyLinkBLEKit
import RileyLinkKit
import os.log

let CellIdentifier = "Cell"

public class RileyLinkSwitch: UISwitch {
    
    public var index: Int = 0
    public var section: Int = 0
}

public class RileyLinkDeviceTableViewController: UITableViewController {

    private let log = OSLog(category: "RileyLinkDeviceTableViewController")

    public let device: RileyLinkDevice

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
    
    
    private var frequency: Measurement<UnitFrequency>? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.frequency)?.setDetailFrequency(frequency, formatter: frequencyFormatter)
        }
    }

    var rssiFetchTimer: Timer? {
        willSet {
            rssiFetchTimer?.invalidate()
        }
    }
    
    private lazy var frequencyFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        
        formatter.numberFormatter = decimalFormatter
        
        return formatter
    }()


    private var appeared = false

    public init(device: RileyLinkDevice) {
        self.device = device

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

    func updateDeviceStatus() {
        device.getStatus { (status) in
            DispatchQueue.main.async {
                self.firmwareVersion = status.firmwareDescription
                self.fw_hw = status.fw_hw
                self.ledOn = status.ledOn
                self.vibrationOn = status.vibrationOn
                self.voltage = status.voltage
                
                self.tableView.reloadData()
            }
        }
    }
    
    func updateUptime() {
        device.runSession(withName: "Get stats for uptime") { (session) in
            do {
                let statistics = try session.getRileyLinkStatistics()
                DispatchQueue.main.async {
                    self.uptime = statistics.uptime
                }
            } catch let error {
                self.log.error("Failed to get stats for uptime: %{public}@", String(describing: error))
            }
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
    
    func orangeReadVDC() {
        device.runSession(withName: "orange Read Set") { (session) in
            self.device.orangeReadVDC()
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

    
    func updateFrequency() {

        device.runSession(withName: "Get base frequency") { (session) in
            do {
                let frequency = try session.readBaseFrequency()
                DispatchQueue.main.async {
                    self.frequency = frequency
                }
            } catch let error {
                self.log.error("Failed to get base frequency: %{public}@", String(describing: error))
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
        
        updateFrequency()

        updateUptime()
        
        updateBatteryLevel()
        
        writePSW()
        
        orangeReadSet()
        
        orangeReadVDC()
        
        orangeAction(index: 9)
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if redOn || yellowOn {
            orangeAction(index: 3)
        }
        
        if shakeOn {
            orangeAction(index: 5)
        }
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
        case alert
        case configureCommand
        case commands
    }
    
    private enum AlertRow: Int, CaseCountable {
        case battery
        case voltage
    }

    private enum DeviceRow: Int, CaseCountable {
        case customName
        case version
        case rssi
        case connection
        case uptime
        case frequency
        case battery
        case orl
        case voltage
    }
    
    private enum CommandRow: Int, CaseCountable {
        case yellow
        case red
        case shake
    }
    
    private enum ConfigureCommandRow: Int, CaseCountable {
        case led
        case vibration
    }

    private func cellForRow(_ row: DeviceRow) -> UITableViewCell? {
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: Section.device.rawValue))
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
        case .commands:
            return CommandRow.count
        case .configureCommand:
            return ConfigureCommandRow.count
        case .alert:
            return AlertRow.count
        }
    }
    
    @objc
    func switchAction(sender: RileyLinkSwitch) {
        switch Section(rawValue: sender.section)! {
        case .commands:
            switch CommandRow(rawValue: sender.index)! {
            case .yellow:
                if sender.isOn {
                    orangeAction(index: 1)
                } else {
                    orangeAction(index: 3)
                }
                yellowOn = sender.isOn
                redOn = false
            case .red:
                if sender.isOn {
                    orangeAction(index: 2)
                } else {
                    orangeAction(index: 3)
                }
                yellowOn = false
                redOn = sender.isOn
            case .shake:
                if sender.isOn {
                    orangeAction(index: 4)
                } else {
                    orangeAction(index: 5)
                }
                shakeOn = sender.isOn
            }
        case .configureCommand:
            switch ConfigureCommandRow(rawValue: sender.index)! {
            case .led:
                orangeAction(index: 0, open: sender.isOn)
                ledOn = sender.isOn
            case .vibration:
                orangeAction(index: 1, open: sender.isOn)
                vibrationOn = sender.isOn
            }
        default:
            break
        }
        tableView.reloadData()
    }
    
    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 45
    }
    
    var yellowOn = false
    var redOn = false
    var shakeOn = false
    private var ledOn: Bool = false
    private var vibrationOn: Bool = false
    var voltage = ""

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
        switchView?.section = indexPath.section
        
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
            case .frequency:
                cell.textLabel?.text = LocalizedString("Frequency", comment: "The title of the cell showing current rileylink frequency")
                cell.setDetailFrequency(frequency, formatter: frequencyFormatter)
            case .battery:
                cell.textLabel?.text = NSLocalizedString("Battery level", comment: "The title of the cell showing battery level")
                cell.setDetailBatteryLevel(battery)
            case .orl:
                cell.textLabel?.text = NSLocalizedString("ORL", comment: "The title of the cell showing ORL")
                cell.detailTextLabel?.text = fw_hw
            case .voltage:
                cell.textLabel?.text = NSLocalizedString("Voltage", comment: "The title of the cell showing ORL")
                cell.detailTextLabel?.text = voltage
            }
        case .alert:
            switch AlertRow(rawValue: indexPath.row)! {
            case .battery:
                var value = "OFF"
                let v = UserDefaults.standard.integer(forKey: "battery_alert_value")
                if v != 0 {
                    value = "\(v)%"
                }
                
                cell.accessoryType = .disclosureIndicator
                cell.textLabel?.text = NSLocalizedString("Low Battery Alert", comment: "The title of the cell showing battery level")
                cell.detailTextLabel?.text = "\(value)"
            case .voltage:
                var value = "OFF"
                let v = UserDefaults.standard.double(forKey: "voltage_alert_value")
                if v != 0 {
                    value = String(format: "%.1f%", v)
                }
                
                cell.accessoryType = .disclosureIndicator
                cell.textLabel?.text = NSLocalizedString("Low Voltage Alert", comment: "The title of the cell showing voltage level")
                cell.detailTextLabel?.text = "\(value)"
            }
        case .commands:
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil
            
            switch CommandRow(rawValue: indexPath.row)! {
            case .yellow:
                switchView?.isHidden = false
                cell.accessoryType = .none
                switchView?.isOn = yellowOn
                cell.textLabel?.text = NSLocalizedString("Lighten Yellow LED", comment: "The title of the cell showing Lighten Yellow LED")
            case .red:
                switchView?.isHidden = false
                cell.accessoryType = .none
                switchView?.isOn = redOn
                cell.textLabel?.text = NSLocalizedString("Lighten Red LED", comment: "The title of the cell showing Lighten Red LED")
            case .shake:
                switchView?.isHidden = false
                switchView?.isOn = shakeOn
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Test Vibrator", comment: "The title of the cell showing Test Vibrator")
            }
        case .configureCommand:
            switch ConfigureCommandRow(rawValue: indexPath.row)! {
            case .led:
                switchView?.isHidden = false
                switchView?.isOn = ledOn
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Enable Connection State LED", comment: "The title of the cell showing Stop Vibrator")
            case .vibration:
                switchView?.isHidden = false
                switchView?.isOn = vibrationOn
                cell.accessoryType = .none
                cell.textLabel?.text = NSLocalizedString("Enable Connection State Vibrator", comment: "The title of the cell showing Stop Vibrator")
            }
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .device:
            return LocalizedString("Device", comment: "The title of the section describing the device")
        case .commands:
            return LocalizedString("Test Commands", comment: "The title of the section describing commands")
        case .configureCommand:
            return LocalizedString("Configure Commands", comment: "The title of the section describing commands")
        case .alert:
            return LocalizedString("Alert", comment: "The title of the section describing commands")
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
        case .commands:
            return device.peripheralState == .connected
        case .configureCommand:
            return device.peripheralState == .connected
        case .alert:
            return true
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
            break
        case .configureCommand:
            break
        case .alert:
            switch AlertRow(rawValue: indexPath.row)! {
            case .battery:
                let alert = UIAlertController.init(title: "Battery level Alert", message: nil, preferredStyle: .actionSheet)
                
                let action = UIAlertAction.init(title: "OFF", style: .default) { _ in
                    UserDefaults.standard.setValue(0, forKey: "battery_alert_value")
                    self.tableView.reloadData()
                }
                
                let action1 = UIAlertAction.init(title: "20", style: .default) { _ in
                    UserDefaults.standard.setValue(20, forKey: "battery_alert_value")
                    self.tableView.reloadData()
                }
                
                let action2 = UIAlertAction.init(title: "30", style: .default) { _ in
                    UserDefaults.standard.setValue(30, forKey: "battery_alert_value")
                    self.tableView.reloadData()
                }
                
                let action3 = UIAlertAction.init(title: "40", style: .default) { _ in
                    UserDefaults.standard.setValue(40, forKey: "battery_alert_value")
                    self.tableView.reloadData()
                }
                
                let action4 = UIAlertAction.init(title: "50", style: .default) { _ in
                    UserDefaults.standard.setValue(50, forKey: "battery_alert_value")
                    self.tableView.reloadData()
                }
                alert.addAction(action)
                alert.addAction(action1)
                alert.addAction(action2)
                alert.addAction(action3)
                alert.addAction(action4)
                present(alert, animated: true, completion: nil)
            case .voltage:
                let alert = UIAlertController.init(title: "Voltage level Alert", message: nil, preferredStyle: .actionSheet)
                
                let action = UIAlertAction.init(title: "OFF", style: .default) { _ in
                    UserDefaults.standard.setValue(0, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action1 = UIAlertAction.init(title: "2.4", style: .default) { _ in
                    UserDefaults.standard.setValue(2.4, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action2 = UIAlertAction.init(title: "2.5", style: .default) { _ in
                    UserDefaults.standard.setValue(2.5, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action3 = UIAlertAction.init(title: "2.6", style: .default) { _ in
                    UserDefaults.standard.setValue(2.6, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action4 = UIAlertAction.init(title: "2.7", style: .default) { _ in
                    UserDefaults.standard.setValue(2.7, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action5 = UIAlertAction.init(title: "2.8", style: .default) { _ in
                    UserDefaults.standard.setValue(2.8, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action6 = UIAlertAction.init(title: "2.9", style: .default) { _ in
                    UserDefaults.standard.setValue(2.9, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                
                let action7 = UIAlertAction.init(title: "3.0", style: .default) { _ in
                    UserDefaults.standard.setValue(3.0, forKey: "voltage_alert_value")
                    self.tableView.reloadData()
                }
                alert.addAction(action)
                alert.addAction(action1)
                alert.addAction(action2)
                alert.addAction(action3)
                alert.addAction(action4)
                alert.addAction(action5)
                alert.addAction(action6)
                alert.addAction(action7)
                present(alert, animated: true, completion: nil)
            }
        }
    }
}


extension RileyLinkDeviceTableViewController: TextFieldTableViewControllerDelegate {
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
    
    func setDetailBatteryLevel(_ batteryLevel: String?) {
        if let unwrappedBatteryLevel = batteryLevel {
            detailTextLabel?.text = unwrappedBatteryLevel + " %"
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setDetailFrequency(_ frequency: Measurement<UnitFrequency>?, formatter: MeasurementFormatter) {
        if let frequency = frequency {
            detailTextLabel?.text = formatter.string(from: frequency)
        } else {
            detailTextLabel?.text = ""
        }
    }

}
