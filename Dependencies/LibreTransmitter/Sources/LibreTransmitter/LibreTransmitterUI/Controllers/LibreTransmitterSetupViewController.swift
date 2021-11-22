//
//  MiaomiaoClientSetupViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Combine
import SwiftUI
import UIKit
import os.log
import HealthKit

public protocol CGMManagerSetupViewController {
    var setupDelegate: CGMManagerSetupViewControllerDelegate? { get set }
}

public protocol CGMManagerSetupViewControllerDelegate: AnyObject {
    func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: LibreTransmitterManager)
}

class LibreTransmitterSetupViewController: UINavigationController,
                                           CGMManagerSetupViewController,

                                           CompletionNotifying {

    weak var setupDelegate: CGMManagerSetupViewControllerDelegate?
    weak var completionDelegate: CompletionDelegate?

    var modeSelection: UIHostingController<ModeSelectionView>!

    fileprivate var logger = Logger.init(subsystem: "no.bjorninge.libre", category: "LibreTransmitterSetupViewController")
    lazy var cgmManager: LibreTransmitterManager? =  LibreTransmitterManager()


    init() {
        SelectionState.shared.selectedStringIdentifier = UserDefaults.standard.preSelectedDevice

        let cancelNotifier = GenericObservableObject()
        let saveNotifier = GenericObservableObject()

        modeSelection = UIHostingController(rootView: ModeSelectionView(cancelNotifier: cancelNotifier, saveNotifier: saveNotifier))


        super.init(rootViewController: modeSelection)


        cancelNotifier.listenOnce { [weak self] in
            self?.cancel()
        }

        saveNotifier.listenOnce { [weak self] in
            self?.save()
        }

    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    deinit {
        logger.debug("dabear LibreTransmitterSetupViewController() deinit was called")
        //cgmManager = nil
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func cancel() {
        completionDelegate?.completionNotifyingDidComplete(self)

    }

    @objc
    private func save() {

        let hasNewDevice = SelectionState.shared.selectedStringIdentifier != UserDefaults.standard.preSelectedDevice
        if hasNewDevice, let newDevice = SelectionState.shared.selectedStringIdentifier {
            logger.debug("dabear: Setupcontroller will set new device to \(newDevice)")
            UserDefaults.standard.preSelectedDevice = newDevice
            SelectionState.shared.selectedUID = nil
            UserDefaults.standard.preSelectedUid = nil

        } else if let newUID = SelectionState.shared.selectedUID {
            // this one is only temporary,
            // as we don't know the bluetooth identifier during nfc setup
            logger.debug("dabear: Setupcontroller will set new libre2 device  to \(newUID)")

            UserDefaults.standard.preSelectedUid = newUID
            SelectionState.shared.selectedUID = nil
            UserDefaults.standard.preSelectedDevice = nil


        } else {

            //this cannot really happen unless you are a developer and have previously
            // stored both preSelectedDevice and selectedUID !
        }

        if let cgmManager = cgmManager {
            logger.debug("dabear: Setupcontroller Saving from setup")
            setupDelegate?.cgmManagerSetupViewController(self, didSetUpCGMManager: cgmManager)

        } else {
            logger.debug("dabear: Setupcontroller not Saving from setup")
        }


        completionDelegate?.completionNotifyingDidComplete(self)
    }
}
