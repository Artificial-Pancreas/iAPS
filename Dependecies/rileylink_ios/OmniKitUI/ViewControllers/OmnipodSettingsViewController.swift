//
//  OmnipodSettingsViewController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 8/5/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import RileyLinkKitUI
import LoopKit
import OmniKit
import LoopKitUI

public class ConfirmationBeepsTableViewCell: TextButtonTableViewCell {

    public func updateTextLabel(enabled: Bool) {
        if enabled {
            self.textLabel?.text = LocalizedString("Disable Confirmation Beeps", comment: "Title text for button to disable confirmation beeps")
        } else {
            self.textLabel?.text = LocalizedString("Enable Confirmation Beeps", comment: "Title text for button to enable confirmation beeps")
        }
    }
    
    override public func loadingStatusChanged() {
        self.isEnabled = !isLoading
    }
}

class OmnipodSettingsViewController: RileyLinkSettingsViewController {

    let pumpManager: OmnipodPumpManager
    
    var statusError: Error?
    
    var podState: PodState? {
        didSet {
            refreshButton.isHidden = !refreshAvailable
        }
    }
    
    var pumpManagerStatus: PumpManagerStatus?
    
    var refreshAvailable: Bool {
        return podState != nil
    }
    
    private var bolusProgressTimer: Timer?
    
    init(pumpManager: OmnipodPumpManager) {
        self.pumpManager = pumpManager
        podState = pumpManager.state.podState
        pumpManagerStatus = pumpManager.status
        
        let devicesSectionIndex = OmnipodSettingsViewController.sectionList(podState).firstIndex(of: .rileyLinks)!

        super.init(rileyLinkPumpManager: pumpManager, devicesSectionIndex: devicesSectionIndex, style: .grouped)
        
        pumpManager.addStatusObserver(self, queue: .main)
        pumpManager.addPodStateObserver(self, queue: .main)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    lazy var suspendResumeTableViewCell: SuspendResumeTableViewCell = {
        let cell = SuspendResumeTableViewCell(style: .default, reuseIdentifier: nil)
        cell.basalDeliveryState = pumpManager.status.basalDeliveryState
        return cell
    }()

    lazy var confirmationBeepsTableViewCell: ConfirmationBeepsTableViewCell = {
        let cell = ConfirmationBeepsTableViewCell(style: .default, reuseIdentifier: nil)
        cell.updateTextLabel(enabled: pumpManager.confirmationBeeps)
        return cell
    }()
    
    var activityIndicator: UIActivityIndicatorView!
    var refreshButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = LocalizedString("Pod Settings", comment: "Title of the pod settings view controller")
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 55
        
        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        tableView.register(AlarmsTableViewCell.self, forCellReuseIdentifier: AlarmsTableViewCell.className)
        tableView.register(ExpirationReminderDateTableViewCell.nib(), forCellReuseIdentifier: ExpirationReminderDateTableViewCell.className)
        
        let podImage = UIImage(named: "PodLarge", in: Bundle(for: OmnipodSettingsViewController.self), compatibleWith: nil)!
        let imageView = UIImageView(image: podImage)
        imageView.contentMode = .center
        imageView.frame.size.height += 18  // feels right
        
        let activityIndicatorStyle: UIActivityIndicatorView.Style
        if #available(iOSApplicationExtension 13.0, *) {
            activityIndicatorStyle = .medium
        } else {
            activityIndicatorStyle = .white
        }
        activityIndicator = UIActivityIndicatorView(style: activityIndicatorStyle)
        activityIndicator.hidesWhenStopped = true

        imageView.addSubview(activityIndicator)
        
        refreshButton = UIButton(type: .custom)
        if #available(iOSApplicationExtension 13.0, *) {
            let medConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .bold, scale: .medium)
            refreshButton.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: medConfig), for: .normal)
            refreshButton.tintColor = .systemFill
        }
        refreshButton.addTarget(self, action: #selector(refreshTapped(_:)), for: .touchUpInside)
        imageView.isUserInteractionEnabled = true
        imageView.addSubview(refreshButton)
        
        let margin: CGFloat = 15

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        let parent = imageView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            activityIndicator.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -margin),
            activityIndicator.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -margin),
            refreshButton.centerYAnchor.constraint(equalTo: activityIndicator.centerYAnchor),
            refreshButton.centerXAnchor.constraint(equalTo: activityIndicator.centerXAnchor),
        ])
        

        tableView.tableHeaderView = imageView
        
        if #available(iOSApplicationExtension 13.0, *) {
            tableView.tableHeaderView?.backgroundColor = .systemBackground
        } else {
            tableView.tableHeaderView?.backgroundColor = UIColor.white
        }

        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:)))
        self.navigationItem.setRightBarButton(button, animated: false)
        
        if self.podState != nil {
            refreshPodStatus(emitConfirmationBeep: false)
        } else {
            refreshButton.isHidden = true
        }
    }

    @objc func doneTapped(_ sender: Any) {
        done()
    }
    
    @objc func refreshTapped(_ sender: Any) {
        refreshPodStatus(emitConfirmationBeep: true)
    }
    
    private func refreshPodStatus(emitConfirmationBeep: Bool) {
        refreshButton.alpha = 0
        activityIndicator.startAnimating()
        pumpManager.refreshStatus(emitConfirmationBeep: emitConfirmationBeep) { (_) in
            DispatchQueue.main.async {
                self.refreshButton.alpha = 1
                self.activityIndicator.stopAnimating()
            }
        }
    }

    private func done() {
        if let nav = navigationController as? SettingsNavigationViewController {
            nav.notifyComplete()
        }
        if let nav = navigationController as? OmnipodPumpManagerSetupViewController {
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

        if let configSectionIdx = self.sections.firstIndex(of: .configuration),
            let replacePodRowIdx = self.configurationRows.firstIndex(of: .replacePod)
        {
            self.tableView.reloadRows(at: [IndexPath(row: replacePodRowIdx, section: configSectionIdx)], with: .none)
        }
        
        super.viewWillAppear(animated)
    }
    
    // MARK: - Formatters
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        dateFormatter.doesRelativeDateFormatting = true
        //dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEE 'at' hm", options: 0, locale: nil)
        return dateFormatter
    }()

    
    // MARK: - Data Source
    
    private enum Section: Int, CaseIterable {
        case status = 0
        case podDetails
        case diagnostics
        case configuration
        case rileyLinks
        case deletePumpManager
    }
    
    private class func sectionList(_ podState: PodState?) -> [Section] {
        if let podState = podState {
            if podState.unfinishedPairing {
                return [.configuration, .rileyLinks]
            } else {
                return [.status, .configuration, .rileyLinks, .podDetails, .diagnostics]
            }
        } else {
            return [.configuration, .rileyLinks, .deletePumpManager]
        }
    }
    
    private var sections: [Section] {
        return OmnipodSettingsViewController.sectionList(podState)
    }
    
    private enum PodDetailsRow: Int, CaseIterable {
        case podAddress = 0
        case podLot
        case podTid
        case piVersion
        case pmVersion
    }
    
    private enum Diagnostics: Int, CaseIterable {
        case readPodStatus = 0
        case playTestBeeps
        case readPulseLog
        case testCommand
    }
    
    private var configurationRows: [ConfigurationRow] {
        if podState == nil || podState?.unfinishedPairing == true {
            return [.replacePod]
        } else {
            return ConfigurationRow.allCases
        }
    }
    
    private enum ConfigurationRow: Int, CaseIterable {
        case suspendResume = 0
        case enableDisableConfirmationBeeps
        case reminder
        case timeZoneOffset
        case insulinType
        case replacePod
    }
    
    fileprivate enum StatusRow: Int, CaseIterable {
        case activatedAt = 0
        case expiresAt
        case bolus
        case basal
        case alarms
        case reservoirLevel
        case deliveredInsulin
    }
    
    // MARK: UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .podDetails:
            return PodDetailsRow.allCases.count
        case .diagnostics:
            return Diagnostics.allCases.count
        case .configuration:
            return configurationRows.count
        case .status:
            return StatusRow.allCases.count
        case .rileyLinks:
            return super.tableView(tableView, numberOfRowsInSection: section)
        case .deletePumpManager:
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .podDetails:
            return LocalizedString("Pod Details", comment: "The title of the device information section in settings")
        case .diagnostics:
            return LocalizedString("Diagnostics", comment: "The title of the configuration section in settings")
        case .configuration:
            return nil
        case .status:
            return nil
        case .rileyLinks:
            return super.tableView(tableView, titleForHeaderInSection: section)
        case .deletePumpManager:
            return " "  // Use an empty string for more dramatic spacing
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch sections[section] {
        case .rileyLinks:
            return super.tableView(tableView, viewForHeaderInSection: section)
        case .podDetails, .diagnostics, .configuration, .status, .deletePumpManager:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .podDetails:
            let podState = self.podState!
            switch PodDetailsRow(rawValue: indexPath.row)! {
            case .podAddress:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Assigned Address", comment: "The title text for the address assigned to the pod")
                cell.detailTextLabel?.text = String(format:"%04X", podState.address)
                return cell
            case .podLot:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Lot", comment: "The title of the cell showing the pod lot id")
                cell.detailTextLabel?.text = String(format:"L%d", podState.lot)
                return cell
            case .podTid:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("TID", comment: "The title of the cell showing the pod TID")
                cell.detailTextLabel?.text = String(format:"%07d", podState.tid)
                return cell
            case .piVersion:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("PI Version", comment: "The title of the cell showing the pod pi version")
                cell.detailTextLabel?.text = podState.piVersion
                return cell
            case .pmVersion:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("PM Version", comment: "The title of the cell showing the pod pm version")
                cell.detailTextLabel?.text = podState.pmVersion
                return cell
            }
        case .diagnostics:
            
            switch Diagnostics(rawValue: indexPath.row)! {
            case .readPodStatus:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Read Pod Status", comment: "The title of the command to read the pod status")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .playTestBeeps:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Play Test Beeps", comment: "The title of the command to play test beeps")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .readPulseLog:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Read Pulse Log", comment: "The title of the command to read the pulse log")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .testCommand:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Test Command", comment: "The title of the command to run the test command")
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        case .configuration:

            switch configurationRows[indexPath.row] {
            case .suspendResume:
                return suspendResumeTableViewCell
            case .enableDisableConfirmationBeeps:
                return confirmationBeepsTableViewCell
            case .reminder:
                let cell = tableView.dequeueReusableCell(withIdentifier: ExpirationReminderDateTableViewCell.className, for: indexPath) as! ExpirationReminderDateTableViewCell
                if let podState = podState, let reminderDate = pumpManager.expirationReminderDate {
                    cell.titleLabel.text = LocalizedString("Expiration Reminder", comment: "The title of the cell showing the pod expiration reminder date")
                    cell.date = reminderDate
                    cell.datePicker.datePickerMode = .dateAndTime
                    #if swift(>=5.2)
                        if #available(iOS 14.0, *) {
                            cell.datePicker.preferredDatePickerStyle = .wheels
                        }
                    #endif
                    cell.datePicker.maximumDate = podState.expiresAt?.addingTimeInterval(-Pod.expirationReminderAlertMinTimeBeforeExpiration)
                    cell.datePicker.minimumDate = podState.expiresAt?.addingTimeInterval(-Pod.expirationReminderAlertMaxTimeBeforeExpiration)
                    cell.datePicker.minuteInterval = 1
                    cell.delegate = self
                }
                return cell
            case .timeZoneOffset:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.textLabel?.text = LocalizedString("Change Time Zone", comment: "The title of the command to change pump time zone")
                
                let localTimeZone = TimeZone.current
                let localTimeZoneName = localTimeZone.abbreviation() ?? localTimeZone.identifier
                
                if let timeZone = pumpManagerStatus?.timeZone {
                    let timeZoneDiff = TimeInterval(timeZone.secondsFromGMT() - localTimeZone.secondsFromGMT())
                    let formatter = DateComponentsFormatter()
                    formatter.allowedUnits = [.hour, .minute]
                    let diffString = timeZoneDiff != 0 ? formatter.string(from: abs(timeZoneDiff)) ?? String(abs(timeZoneDiff)) : ""
                    
                    cell.detailTextLabel?.text = String(format: LocalizedString("%1$@%2$@%3$@", comment: "The format string for displaying an offset from a time zone: (1: GMT)(2: -)(3: 4:00)"), localTimeZoneName, timeZoneDiff != 0 ? (timeZoneDiff < 0 ? "-" : "+") : "", diffString)
                }
                cell.accessoryType = .disclosureIndicator
                return cell
            case .insulinType:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                cell.prepareForReuse()
                cell.textLabel?.text = "Insulin Type"
                cell.detailTextLabel?.text = pumpManager.insulinType?.brandName
                cell.accessoryType = .disclosureIndicator
                return cell
            case .replacePod:
                let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
                if podState == nil {
                    cell.textLabel?.text = LocalizedString("Pair New Pod", comment: "The title of the command to pair new pod")
                } else if let podState = podState, podState.isFaulted {
                    cell.textLabel?.text = LocalizedString("Replace Pod Now", comment: "The title of the command to replace pod when there is a pod fault")
                } else if let podState = podState, podState.unfinishedPairing {
                    cell.textLabel?.text = LocalizedString("Finish pod setup", comment: "The title of the command to finish pod setup")
                } else {
                    cell.textLabel?.text = LocalizedString("Replace Pod", comment: "The title of the command to replace pod")
                    cell.tintColor = .deleteColor
                }

                cell.isEnabled = true
                return cell
            }
            
        case .status:
            let podState = self.podState!
            let statusRow = StatusRow(rawValue: indexPath.row)!
            if statusRow == .alarms {
                let cell = tableView.dequeueReusableCell(withIdentifier: AlarmsTableViewCell.className, for: indexPath) as! AlarmsTableViewCell
                cell.textLabel?.text = LocalizedString("Alarms", comment: "The title of the cell showing alarm status")
                cell.alerts = podState.activeAlerts
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                
                switch statusRow {
                case .activatedAt:
                    let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                    cell.textLabel?.text = LocalizedString("Active Time", comment: "The title of the cell showing the pod activated at time")
                    cell.setDetailAge(podState.activatedAt?.timeIntervalSinceNow)
                    return cell
                case .expiresAt:
                    let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
                    if let expiresAt = podState.expiresAt {
                        if expiresAt.timeIntervalSinceNow > 0 {
                            cell.textLabel?.text = LocalizedString("Expires", comment: "The title of the cell showing the pod expiration")
                        } else {
                            cell.textLabel?.text = LocalizedString("Expired", comment: "The title of the cell showing the pod expiration after expiry")
                        }
                    }
                    cell.setDetailDate(podState.expiresAt, formatter: dateFormatter)
                    return cell
                case .bolus:
                    cell.textLabel?.text = LocalizedString("Bolus Delivery", comment: "The title of the cell showing pod bolus status")

                    let deliveredUnits: Double?
                    if let dose = podState.unfinalizedBolus {
                        deliveredUnits = pumpManager.roundToSupportedBolusVolume(units: dose.progress * dose.units)
                    } else {
                        deliveredUnits = nil
                    }

                    cell.setDetailBolus(suspended: podState.isSuspended, dose: podState.unfinalizedBolus, deliveredUnits: deliveredUnits)
                    // TODO: This timer is in the wrong context; should be part of a custom bolus progress cell
//                    if bolusProgressTimer == nil {
//                        bolusProgressTimer = Timer.scheduledTimer(withTimeInterval: .seconds(2), repeats: true) { [weak self] (_) in
//                            self?.tableView.reloadRows(at: [indexPath], with: .none)
//                        }
//                    }
                case .basal:
                    cell.textLabel?.text = LocalizedString("Basal Delivery", comment: "The title of the cell showing pod basal status")
                    cell.setDetailBasal(suspended: podState.isSuspended, dose: podState.unfinalizedTempBasal)
                case .reservoirLevel:
                    cell.textLabel?.text = LocalizedString("Reservoir", comment: "The title of the cell showing reservoir status")
                    cell.setReservoirDetail(podState.lastInsulinMeasurements)
                case .deliveredInsulin:
                    cell.textLabel?.text = LocalizedString("Insulin Delivered", comment: "The title of the cell showing delivered insulin")
                    cell.setDeliveredInsulinDetail(podState.lastInsulinMeasurements)
                default:
                    break
                }
                return cell
            }
        case .rileyLinks:
            return super.tableView(tableView, cellForRowAt: indexPath)
        case .deletePumpManager:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
            
            cell.textLabel?.text = LocalizedString("Switch from Omnipod Pumps", comment: "Title text for the button to delete Omnipod PumpManager")
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .deleteColor
            cell.isEnabled = true
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch sections[indexPath.section] {
        case .podDetails:
            return false
        case .status:
            switch StatusRow(rawValue: indexPath.row)! {
            case .alarms:
                return true
            default:
                return false
            }
        case .diagnostics, .configuration, .rileyLinks, .deletePumpManager:
            return true
        }
    }


    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath == IndexPath(row: ConfigurationRow.reminder.rawValue, section: Section.configuration.rawValue) {
            tableView.beginUpdates()
        }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)
        
        switch sections[indexPath.section] {
        case .podDetails:
            break
        case .diagnostics:
            switch Diagnostics(rawValue: indexPath.row)! {
            case .readPodStatus:
                let vc = CommandResponseViewController.readPodStatus(pumpManager: pumpManager)
                vc.title = sender?.textLabel?.text
                show(vc, sender: indexPath)
            case .playTestBeeps:
                let vc = CommandResponseViewController.playTestBeeps(pumpManager: pumpManager)
                vc.title = sender?.textLabel?.text
                show(vc, sender: indexPath)
            case .readPulseLog:
                let vc = CommandResponseViewController.readPulseLog(pumpManager: pumpManager)
                vc.title = sender?.textLabel?.text
                show(vc, sender: indexPath)
            case .testCommand:
                let vc = CommandResponseViewController.testingCommands(pumpManager: pumpManager)
                vc.title = sender?.textLabel?.text
                show(vc, sender: indexPath)
            }
        case .status:
            switch StatusRow(rawValue: indexPath.row)! {
            case .alarms:
                if let cell = tableView.cellForRow(at: indexPath) as? AlarmsTableViewCell {
                    let activeSlots = AlertSet(slots: Array(cell.alerts.keys))
                    if activeSlots.count > 0 {
                        cell.isLoading = true
                        cell.isEnabled = false
                        pumpManager.acknowledgeAlerts(activeSlots) { (updatedAlerts) in
                            DispatchQueue.main.async {
                                cell.isLoading = false
                                cell.isEnabled = true
                                if let updatedAlerts = updatedAlerts {
                                    cell.alerts = updatedAlerts
                                }
                            }
                        }
                    }
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            default:
                break
            }
        case .configuration:
            switch configurationRows[indexPath.row] {
            case .suspendResume:
                suspendResumeTapped()
                tableView.deselectRow(at: indexPath, animated: true)
            case .enableDisableConfirmationBeeps:
                confirmationBeepsTapped()
                tableView.deselectRow(at: indexPath, animated: true)
            case .reminder:
                tableView.deselectRow(at: indexPath, animated: true)
                tableView.endUpdates()
                break
            case .timeZoneOffset:
                let vc = CommandResponseViewController.changeTime(pumpManager: pumpManager)
                vc.title = sender?.textLabel?.text
                show(vc, sender: indexPath)
            case .insulinType:
                let view = InsulinTypeSetting(initialValue: pumpManager.insulinType ?? .novolog, supportedInsulinTypes: InsulinType.allCases) { (newType) in
                    self.pumpManager.insulinType = newType
                }
                let vc = DismissibleHostingController(rootView: view)
                vc.title = LocalizedString("Insulin Type", comment: "Controller title for insulin type selection screen")
                show(vc, sender: sender)
            case .replacePod:
                let vc: UIViewController
                if podState == nil || podState!.setupProgress.primingNeeded {
                    vc = PodReplacementNavigationController.instantiateNewPodFlow(pumpManager)
                } else if let podState = podState, podState.isFaulted {
                    vc = PodReplacementNavigationController.instantiatePodReplacementFlow(pumpManager)
                } else if let podState = podState, podState.unfinishedPairing {
                    vc = PodReplacementNavigationController.instantiateInsertCannulaFlow(pumpManager)
                } else {
                    vc = PodReplacementNavigationController.instantiatePodReplacementFlow(pumpManager)
                }
                if var completionNotifying = vc as? CompletionNotifying {
                    completionNotifying.completionDelegate = self
                }
                self.navigationController?.present(vc, animated: true, completion: nil)
            }
        case .rileyLinks:
            let device = devicesDataSource.devices[indexPath.row]
            let vc = RileyLinkDeviceTableViewController(device: device)
            self.show(vc, sender: sender)
        case .deletePumpManager:
            let confirmVC = UIAlertController(pumpManagerDeletionHandler: {
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
        switch sections[indexPath.section] {
        case .podDetails, .status:
            break
        case .diagnostics:
            switch Diagnostics(rawValue: indexPath.row)! {
            case .readPodStatus, .playTestBeeps, .readPulseLog, .testCommand:
                tableView.reloadRows(at: [indexPath], with: .fade)
            }
        case .configuration:
            switch configurationRows[indexPath.row] {
            case .suspendResume, .enableDisableConfirmationBeeps, .reminder:
                break
            case .timeZoneOffset, .replacePod, .insulinType:
                tableView.reloadRows(at: [indexPath], with: .fade)
            }
        case .rileyLinks:
            break
        case .deletePumpManager:
            break
        }
        
        return indexPath
    }

    private func suspendResumeTapped() {
        switch suspendResumeTableViewCell.shownAction {
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

    private func confirmationBeepsTapped() {
        let confirmationBeeps: Bool = pumpManager.confirmationBeeps
        
        func done() {
            DispatchQueue.main.async { [weak self] in
                if let self = self {
                    self.confirmationBeepsTableViewCell.updateTextLabel(enabled: self.pumpManager.confirmationBeeps)
                    self.confirmationBeepsTableViewCell.isLoading = false
                }
            }
        }

        confirmationBeepsTableViewCell.isLoading = true
        if confirmationBeeps {
            pumpManager.setConfirmationBeeps(enabled: false, completion: { (error) in
                if let error = error {
                    DispatchQueue.main.async {
                        let title = LocalizedString("Error disabling confirmation beeps", comment: "The alert title for disable confirmation beeps error")
                        self.present(UIAlertController(with: error, title: title), animated: true)
                    }
                }
                done()
            })
        } else {
            pumpManager.setConfirmationBeeps(enabled: true, completion: { (error) in
                if let error = error {
                    DispatchQueue.main.async {
                        let title = LocalizedString("Error enabling confirmation beeps", comment: "The alert title for enable confirmation beeps error")
                        self.present(UIAlertController(with: error, title: title), animated: true)
                    }
                }
                done()
            })
        }
    }
}

extension OmnipodSettingsViewController: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        if let vc = object as? UIViewController, vc === presentedViewController {
            dismiss(animated: true, completion: nil)
        }
    }
}

extension OmnipodSettingsViewController: RadioSelectionTableViewControllerDelegate {
    func radioSelectionTableViewControllerDidChangeSelectedIndex(_ controller: RadioSelectionTableViewController) {
        guard let indexPath = self.tableView.indexPathForSelectedRow else {
            return
        }
        
        switch sections[indexPath.section] {
        case .configuration:
            switch configurationRows[indexPath.row] {
            default:
                assertionFailure()
            }
        default:
            assertionFailure()
        }
        
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

extension OmnipodSettingsViewController: PodStateObserver {
    func podStateDidUpdate(_ state: PodState?) {
        let newSections = OmnipodSettingsViewController.sectionList(state)
        let sectionsChanged = OmnipodSettingsViewController.sectionList(self.podState) != newSections

        let oldConfigurationRowsCount = self.configurationRows.count
        let oldState = self.podState
        self.podState = state

        if sectionsChanged {
            self.devicesDataSource.devicesSectionIndex = self.sections.firstIndex(of: .rileyLinks)!
            self.tableView.reloadData()
        } else {
            if oldConfigurationRowsCount != self.configurationRows.count, let idx = newSections.firstIndex(of: .configuration) {
                self.tableView.reloadSections([idx], with: .fade)
            }
        }

        guard let statusIdx = newSections.firstIndex(of: .status) else {
            return
        }

        let reloadRows: [StatusRow] = [.bolus, .basal, .reservoirLevel, .deliveredInsulin]
        self.tableView.reloadRows(at: reloadRows.map({ IndexPath(row: $0.rawValue, section: statusIdx) }), with: .none)

        if oldState?.activeAlerts != state?.activeAlerts,
            let alerts = state?.activeAlerts,
            let alertCell = self.tableView.cellForRow(at: IndexPath(row: StatusRow.alarms.rawValue, section: statusIdx)) as? AlarmsTableViewCell
        {
            alertCell.alerts = alerts
        }
    }
}

extension OmnipodSettingsViewController: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        self.pumpManagerStatus = status
        self.suspendResumeTableViewCell.basalDeliveryState = status.basalDeliveryState
        if let statusSectionIdx = self.sections.firstIndex(of: .status) {
            self.tableView.reloadSections([statusSectionIdx], with: .none)
        }
    }
}

extension OmnipodSettingsViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        pumpManager.expirationReminderDate = cell.date
    }
}

private extension UIAlertController {
    convenience init(pumpManagerDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to stop using Omnipod?", comment: "Confirmation message for removing Omnipod PumpManager"),
            preferredStyle: .actionSheet
        )
        
        addAction(UIAlertAction(
            title: LocalizedString("Delete Omnipod", comment: "Button title to delete Omnipod PumpManager"),
            style: .destructive,
            handler: { (_) in
                handler()
        }
        ))
        
        let cancel = LocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
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

class AlarmsTableViewCell: LoadingTableViewCell {
    
    private var defaultDetailColor: UIColor?

    override public init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
        detailTextLabel?.tintAdjustmentMode = .automatic
        defaultDetailColor = detailTextLabel?.textColor
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    private func updateColor() {
        if alerts.count == 0 {
            detailTextLabel?.textColor = defaultDetailColor
        } else {
            detailTextLabel?.textColor = tintColor
        }
    }
    
    public var isEnabled = true {
        didSet {
            selectionStyle = isEnabled ? .default : .none
        }
    }
    
    override public func loadingStatusChanged() {
        self.detailTextLabel?.isHidden = isLoading
    }
    
    var alerts = [AlertSlot: PodAlert]() {
        didSet {
            updateColor()
            if alerts.isEmpty {
                detailTextLabel?.text = LocalizedString("None", comment: "Alerts detail when no alerts unacknowledged")
            } else {
                detailTextLabel?.text = alerts.map { slot, alert in String.init(describing: alert) }.joined(separator: ", ")
            }
        }
    }
    
    open override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }
    
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColor()
    }

}


private extension UITableViewCell {
    
    private var insulinFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }
    
    private var percentFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }


    func setDetailDate(_ date: Date?, formatter: DateFormatter) {
        if let date = date {
            detailTextLabel?.text = formatter.string(from: date)
        } else {
            detailTextLabel?.text = "-"
        }
    }
    
    func setDetailAge(_ age: TimeInterval?) {
        if let age = age {
            detailTextLabel?.text = fabs(age).format(using: [.day, .hour, .minute])
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setDetailBasal(suspended: Bool, dose: UnfinalizedDose?) {
        if suspended {
            detailTextLabel?.text = LocalizedString("Suspended", comment: "The detail text of the basal row when pod is suspended")
        } else if let dose = dose {
            if let rate = insulinFormatter.string(from: dose.rate) {
                detailTextLabel?.text = String(format: LocalizedString("%@ U/hour", comment: "Format string for temp basal rate. (1: The localized amount)"), rate)
            }
        } else {
            detailTextLabel?.text = LocalizedString("Schedule", comment: "The detail text of the basal row when pod is running scheduled basal")
        }
    }
    
    func setDetailBolus(suspended: Bool, dose: UnfinalizedDose?, deliveredUnits: Double?) {
        guard let dose = dose, let delivered = deliveredUnits, !suspended else {
            detailTextLabel?.text = LocalizedString("None", comment: "The detail text for bolus delivery when no bolus is being delivered")
            return
        }
        
        let progress = dose.progress
        if let units = self.insulinFormatter.string(from: dose.units), let deliveredUnits = self.insulinFormatter.string(from: delivered) {
            if progress >= 1 {
                self.detailTextLabel?.text = String(format: LocalizedString("%@ U (Finished)", comment: "Format string for bolus progress when finished. (1: The localized amount)"), units)
            } else {
                let progressFormatted = percentFormatter.string(from: progress * 100.0) ?? ""
                let progressStr = String(format: LocalizedString("%@%%", comment: "Format string for bolus percent progress. (1: Percent progress)"), progressFormatted)
                self.detailTextLabel?.text = String(format: LocalizedString("%@ U of %@ U (%@)", comment: "Format string for bolus progress. (1: The delivered amount) (2: The programmed amount) (3: the percent progress)"), deliveredUnits, units, progressStr)
            }
        }


    }
    
    func setDeliveredInsulinDetail(_ measurements: PodInsulinMeasurements?) {
        guard let measurements = measurements else {
            detailTextLabel?.text = LocalizedString("Unknown", comment: "The detail text for delivered insulin when no measurement is available")
            return
        }
        if let units = insulinFormatter.string(from: measurements.delivered) {
            detailTextLabel?.text = String(format: LocalizedString("%@ U", comment: "Format string for delivered insulin. (1: The localized amount)"), units)
        }
    }

    func setReservoirDetail(_ measurements: PodInsulinMeasurements?) {
        guard let measurements = measurements else {
            detailTextLabel?.text = LocalizedString("Unknown", comment: "The detail text for delivered insulin when no measurement is available")
            return
        }
        if measurements.reservoirLevel == nil {
            if let units = insulinFormatter.string(from: Pod.maximumReservoirReading) {
                detailTextLabel?.text = String(format: LocalizedString("%@+ U", comment: "Format string for reservoir reading when above or equal to maximum reading. (1: The localized amount)"), units)
            }
        } else {
            if let reservoirValue = measurements.reservoirLevel,
                let units = insulinFormatter.string(from: reservoirValue)
            {
                detailTextLabel?.text = String(format: LocalizedString("%@ U", comment: "Format string for insulin remaining in reservoir. (1: The localized amount)"), units)
            }
        }
    }
}

