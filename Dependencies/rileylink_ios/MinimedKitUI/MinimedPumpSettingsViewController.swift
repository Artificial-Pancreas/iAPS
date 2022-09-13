//
//  MinimedPumpSettingsViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI
import MinimedKit
import RileyLinkBLEKit
import RileyLinkKitUI
import LoopKit

class MinimedPumpSettingsViewController: RileyLinkSettingsViewController {

    let pumpManager: MinimedPumpManager

    let supportedInsulinTypes: [InsulinType]
    
    private var ops: PumpOps {
        return pumpManager.pumpOps
    }

    // MARK: - Formatters

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()

        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .medium

        return dateFormatter
    }()
    
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
    
    private lazy var integerFormatter = NumberFormatter()
    
    private func cellForRow(_ row: CommandsRow) -> UITableViewCell? {
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: Section.commands.rawValue))
    }
    
    private var pumpState: PumpState? {
        didSet {
            if let cell = cellForRow(.tune) {
                cell.setTuneInfo(lastValidFrequency: pumpState?.lastValidFrequency, lastTuned: pumpState?.lastTuned, measurementFormatter: measurementFormatter, dateFormatter: dateFormatter)
            }
        }
    }

    
    init(pumpManager: MinimedPumpManager, supportedInsulinTypes: [InsulinType]) {
        self.pumpManager = pumpManager
        self.supportedInsulinTypes = supportedInsulinTypes
        super.init(rileyLinkPumpManager: pumpManager, devicesSectionIndex: Section.rileyLinks.rawValue, style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = LocalizedString("Pump Settings", comment: "Title of the pump settings view controller")

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44

        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 55

        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        tableView.register(SuspendResumeTableViewCell.self, forCellReuseIdentifier: SuspendResumeTableViewCell.className)

        let imageView = UIImageView(image: pumpManager.state.largePumpImage)
        imageView.contentMode = .bottom
        imageView.frame.size.height += 18  // feels right
        tableView.tableHeaderView = imageView
        
        let center = NotificationCenter.default
        let mainQueue = OperationQueue.main

        center.addObserver(forName: .PumpOpsStateDidChange, object: pumpManager.pumpOps, queue: mainQueue) { [weak self] (note) in
            if let state = note.userInfo?[MinimedPumpOps.notificationPumpStateKey] as? PumpState {
                self?.pumpState = state
            }
        }

        pumpManager.addStatusObserver(self, queue: .main)

        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:)))
        self.navigationItem.setRightBarButton(button, animated: false)
        
        self.pumpState = pumpManager.state.pumpState
    }

    @objc func doneTapped(_ sender: Any) {
        done()
    }

    private func done() {
        if let nav = navigationController as? SettingsNavigationViewController {
            nav.notifyComplete()
        }
        if let nav = navigationController as? MinimedPumpManagerSetupViewController {
            nav.finishedSettingsDisplay()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        if clearsSelectionOnViewWillAppear {
            // Manually invoke the delegate for rows deselecting on appear
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                _ = tableView(tableView, willDeselectRowAt: indexPath)
            }
        }

        super.viewWillAppear(animated)
    }

    // MARK: - Data Source

    private enum Section: Int, CaseIterable {
        case info = 0
        case actions
        case settings
        case rileyLinks
        case commands
        case delete
    }

    private enum InfoRow: Int, CaseIterable {
        case pumpID = 0
        case pumpModel
        case pumpFirmware
        case pumpRegion
    }

    private enum ActionsRow: Int, CaseIterable {
        case suspendResume = 0
    }

    private enum SettingsRow: Int, CaseIterable {
        case timeZoneOffset = 0
        case batteryChemistry
        case preferredInsulinDataSource
        case insulinType
        // This should always be last so it can be omitted for non-MySentry pumps:
        case useMySentry
    }
    
    private enum CommandsRow: Int, CaseIterable {
        case tune
        case mySentryPair
        case dumpHistory
        case fetchGlucose
        case getPumpModel
        case pressDownButton
        case readPumpStatus
        case readBasalSchedule
    }


    // MARK: UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .info:
            return InfoRow.allCases.count
        case .actions:
            return ActionsRow.allCases.count
        case .settings:
            let settingsRowCount = pumpManager.state.pumpModel.hasMySentry ? SettingsRow.allCases.count : SettingsRow.allCases.count - 1
            return settingsRowCount
        case .rileyLinks:
            return super.tableView(tableView, numberOfRowsInSection: section)
        case .commands:
            return CommandsRow.allCases.count
        case .delete:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .settings:
            return LocalizedString("Configuration", comment: "The title of the configuration section in MinimedPumpManager settings")
        case .rileyLinks:
            return super.tableView(tableView, titleForHeaderInSection: section)
        case .commands:
            return LocalizedString("Commands", comment: "The title of the commands section in MinimedPumpManager settings")
        case .delete:
            return " "  // Use an empty string for more dramatic spacing
        case .info, .actions:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .rileyLinks:
            return super.tableView(tableView, viewForHeaderInSection: section)
        case .info, .settings, .delete, .actions, .commands:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .info:
            switch InfoRow(rawValue: indexPath.row)! {
            case .pumpID:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                cell.detailTextLabel?.text = pumpManager.state.pumpID
                return cell
            case .pumpModel:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Pump Model", comment: "The title of the cell showing the pump model number")
                cell.detailTextLabel?.text = String(describing: pumpManager.state.pumpModel)
                return cell
            case .pumpFirmware:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Firmware Version", comment: "The title of the cell showing the pump firmware version")
                cell.detailTextLabel?.text = String(describing: pumpManager.state.pumpFirmwareVersion)
                return cell
            case .pumpRegion:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Region", comment: "The title of the cell showing the pump region")
                cell.detailTextLabel?.text = String(describing: pumpManager.state.pumpRegion)
                return cell
            }
        case .actions:
            switch ActionsRow(rawValue: indexPath.row)! {
            case .suspendResume:
                let cell = tableView.dequeueReusableCell(withIdentifier: SuspendResumeTableViewCell.className, for: indexPath) as! SuspendResumeTableViewCell
                cell.basalDeliveryState = pumpManager.status.basalDeliveryState
                return cell
            }
        case .settings:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)

            switch SettingsRow(rawValue: indexPath.row)! {
            case .batteryChemistry:
                cell.textLabel?.text = LocalizedString("Pump Battery Type", comment: "The title text for the battery type value")
                cell.detailTextLabel?.text = String(describing: pumpManager.batteryChemistry)
            case .preferredInsulinDataSource:
                cell.textLabel?.text = LocalizedString("Preferred Data Source", comment: "The title text for the preferred insulin data source config")
                cell.detailTextLabel?.text = String(describing: pumpManager.preferredInsulinDataSource)
            case .useMySentry:
                cell.textLabel?.text = LocalizedString("Use MySentry", comment: "The title text for the preferred MySentry setting config")
                cell.detailTextLabel?.text = pumpManager.useMySentry ? "Yes" : "No"
            case .timeZoneOffset:
                cell.textLabel?.text = LocalizedString("Change Time Zone", comment: "The title of the command to change pump time zone")

                let localTimeZone = TimeZone.current
                let localTimeZoneName = localTimeZone.abbreviation() ?? localTimeZone.identifier

                let timeZoneDiff = TimeInterval(pumpManager.state.timeZone.secondsFromGMT() - localTimeZone.secondsFromGMT())
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute]
                let diffString = timeZoneDiff != 0 ? formatter.string(from: abs(timeZoneDiff)) ?? String(abs(timeZoneDiff)) : ""

                cell.detailTextLabel?.text = String(format: LocalizedString("%1$@%2$@%3$@", comment: "The format string for displaying an offset from a time zone: (1: GMT)(2: -)(3: 4:00)"), localTimeZoneName, timeZoneDiff != 0 ? (timeZoneDiff < 0 ? "-" : "+") : "", diffString)
            case .insulinType:
                cell.prepareForReuse()
                cell.textLabel?.text = "Insulin Type"
                cell.detailTextLabel?.text = pumpManager.insulinType?.brandName
            }

            cell.accessoryType = .disclosureIndicator
            return cell
        case .rileyLinks:
            return super.tableView(tableView, cellForRowAt: indexPath)
        case .commands:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)

            switch CommandsRow(rawValue: indexPath.row)! {
            case .tune:
                cell.setTuneInfo(lastValidFrequency: pumpState?.lastValidFrequency, lastTuned: pumpState?.lastTuned, measurementFormatter: measurementFormatter, dateFormatter: dateFormatter)
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
            
            }
            return cell

        case .delete:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell

            cell.textLabel?.text = LocalizedString("Delete Pump", comment: "Title text for the button to remove a pump from Loop")
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .deleteColor
            cell.isEnabled = true
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section)! {
        case .info:
            return false
        case .actions, .settings, .rileyLinks, .delete, .commands:
            return true
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)

        switch Section(rawValue: indexPath.section)! {
        case .info:
            break
        case .actions:
            switch ActionsRow(rawValue: indexPath.row)! {
            case .suspendResume:
                suspendResumeCellTapped(sender as! SuspendResumeTableViewCell)
                tableView.deselectRow(at: indexPath, animated: true)
            }
        case .settings:
            switch SettingsRow(rawValue: indexPath.row)! {
            case .timeZoneOffset:
                let vc = CommandResponseViewController.changeTime(ops: pumpManager.pumpOps, rileyLinkDeviceProvider: pumpManager.rileyLinkDeviceProvider)
                vc.title = sender?.textLabel?.text

                show(vc, sender: indexPath)
            case .batteryChemistry:
                let vc = RadioSelectionTableViewController.batteryChemistryType(pumpManager.batteryChemistry)
                vc.title = sender?.textLabel?.text
                vc.delegate = self

                show(vc, sender: sender)
            case .preferredInsulinDataSource:
                let vc = RadioSelectionTableViewController.insulinDataSource(pumpManager.preferredInsulinDataSource)
                vc.title = sender?.textLabel?.text
                vc.delegate = self

                show(vc, sender: sender)
            case .insulinType:
                let view = InsulinTypeSetting(initialValue: pumpManager.insulinType ?? .novolog, supportedInsulinTypes: supportedInsulinTypes, allowUnsetInsulinType: false) { (newType) in
                    self.pumpManager.insulinType = newType
                }
                let vc = DismissibleHostingController(rootView: view)
                vc.title = LocalizedString("Insulin Type", comment: "Controller title for insulin type selection screen")
                
                show(vc, sender: sender)
            case .useMySentry:
                let vc = RadioSelectionTableViewController.useMySentry(pumpManager.useMySentry)
                vc.title = sender?.textLabel?.text
                vc.delegate = self
                show(vc, sender: sender)
            }
        case .rileyLinks:
            let device = devicesDataSource.devices[indexPath.row]
            
            guard device.hardwareType != nil else {
                tableView.deselectRow(at: indexPath, animated: true)
                return
            }

            let vc = RileyLinkDeviceTableViewController(
                device: device,
                batteryAlertLevel: pumpManager.rileyLinkBatteryAlertLevel,
                batteryAlertLevelChanged: { [weak self] value in
                    self?.pumpManager.rileyLinkBatteryAlertLevel = value
                }
            )

            self.show(vc, sender: sender)
        case .commands:
            pumpManager.rileyLinkDeviceProvider.firstConnectedDevice { device in
                DispatchQueue.main.async {
                    if let device = device,
                       let cell = tableView.cellForRow(at: indexPath),
                       let title = cell.textLabel?.text
                    {
                        self.runCommand(CommandsRow(rawValue: indexPath.row)!, device: device, title: title)
                    }
                }
            }
        case .delete:
            let confirmVC = UIAlertController(pumpDeletionHandler: {
                self.pumpManager.notifyDelegateOfDeactivation {
                    DispatchQueue.main.async {
                        self.done()
                    }
                }
            })

            present(confirmVC, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    override func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        switch Section(rawValue: indexPath.section)! {
        case .settings:
            switch SettingsRow(rawValue: indexPath.row)! {
            case .timeZoneOffset, .insulinType:
                tableView.reloadRows(at: [indexPath], with: .fade)
            case .batteryChemistry:
                break
            case .preferredInsulinDataSource:
                break
            case .useMySentry:
                break
            }
        case .info, .actions, .rileyLinks, .delete, .commands:
            break
        }

        return indexPath
    }
    
    private func runCommand(_ command: CommandsRow, device: RileyLinkDevice, title: String) {
        var vc: CommandResponseViewController?

        switch command {
        case .tune:
            vc = .tuneRadio(ops: ops, device: device, measurementFormatter: measurementFormatter)
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
        }
        
        vc?.title = title

        if let vc = vc {
            show(vc, sender: nil)
        }

    }
}


extension MinimedPumpSettingsViewController: RadioSelectionTableViewControllerDelegate {
    func radioSelectionTableViewControllerDidChangeSelectedIndex(_ controller: RadioSelectionTableViewController) {
        guard let indexPath = self.tableView.indexPathForSelectedRow else {
            return
        }

        switch Section(rawValue: indexPath.section)! {
        case .settings:
            switch SettingsRow(rawValue: indexPath.row)! {
            case .preferredInsulinDataSource:
                if let selectedIndex = controller.selectedIndex, let dataSource = InsulinDataSource(rawValue: selectedIndex) {
                    pumpManager.preferredInsulinDataSource = dataSource
                }
            case .batteryChemistry:
                if let selectedIndex = controller.selectedIndex, let dataSource = MinimedKit.BatteryChemistryType(rawValue: selectedIndex) {
                    pumpManager.batteryChemistry = dataSource
                }
            case .useMySentry:
                if let selectedIndex = controller.selectedIndex {
                    pumpManager.useMySentry = selectedIndex == 0
                }
            default:
                assertionFailure()
            }
        default:
            assertionFailure()
        }

        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func suspendResumeCellTapped(_ cell: SuspendResumeTableViewCell) {
        guard cell.isEnabled else {
            return
        }
        
        switch cell.shownAction {
        case .resume:
            pumpManager.resumeDelivery { (error) in
                if let error = error {
                    DispatchQueue.main.async {
                        let title = LocalizedString("Error Resuming", comment: "The alert title for a resume error")
                        self.present(UIAlertController(with: error, title: title), animated: true)
                    }
                }
            }
        case .suspend:
            pumpManager.suspendDelivery { (error) in
                if let error = error {
                    DispatchQueue.main.async {
                        let title = LocalizedString("Error Suspending", comment: "The alert title for a suspend error")
                        self.present(UIAlertController(with: error, title: title), animated: true)
                    }
                }
            }
        default:
            break
        }
    }
}

extension MinimedPumpSettingsViewController: PumpManagerStatusObserver {
    public func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let suspendResumeTableViewCell = self.tableView?.cellForRow(at: IndexPath(row: ActionsRow.suspendResume.rawValue, section: Section.actions.rawValue)) as? SuspendResumeTableViewCell
        {
            suspendResumeTableViewCell.basalDeliveryState = status.basalDeliveryState
        }
    }
}

private extension UIAlertController {
    convenience init(pumpDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to delete this pump?", comment: "Confirmation message for deleting a pump"),
            preferredStyle: .actionSheet
        )

        addAction(UIAlertAction(
            title: LocalizedString("Delete Pump", comment: "Button title to delete pump"),
            style: .destructive,
            handler: { (_) in
                handler()
            }
        ))

        let cancel = LocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
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

    func setTuneInfo(lastValidFrequency: Measurement<UnitFrequency>?, lastTuned: Date?, measurementFormatter: MeasurementFormatter, dateFormatter: DateFormatter) {
        if let frequency = lastValidFrequency, let date = lastTuned {
            textLabel?.text = measurementFormatter.string(from: frequency)
            setDetailDate(date, formatter: dateFormatter)
        } else {
            textLabel?.text = LocalizedString("Tune Radio Frequency", comment: "The title of the command to re-tune the radio")
        }
    }
}
