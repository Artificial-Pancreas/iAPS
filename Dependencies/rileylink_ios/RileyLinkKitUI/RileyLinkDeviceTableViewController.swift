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
    
    private var uptime: TimeInterval? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.uptime)?.setDetailAge(uptime)
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
        case commands
    }

    private enum DeviceRow: Int, CaseCountable {
        case customName
        case version
        case rssi
        case connection
        case uptime
        case frequency
    }

    private func cellForRow(_ row: DeviceRow) -> UITableViewCell? {
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: Section.device.rawValue))
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .device:
            return DeviceRow.count
        case .commands:
            return 0
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        if let reusableCell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier) {
            cell = reusableCell
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: CellIdentifier)
        }

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
            }
        case .commands:
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .device:
            return LocalizedString("Device", comment: "The title of the section describing the device")
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
            break
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
    
    func setDetailFrequency(_ frequency: Measurement<UnitFrequency>?, formatter: MeasurementFormatter) {
        if let frequency = frequency {
            detailTextLabel?.text = formatter.string(from: frequency)
        } else {
            detailTextLabel?.text = ""
        }
    }

}
