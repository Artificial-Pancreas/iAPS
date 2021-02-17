//
//  MinimedPumpSetupCompleteViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI

class MinimedPumpSetupCompleteViewController: SetupTableViewController {

    @IBOutlet private var pumpImageView: UIImageView!

    var pumpImage: UIImage? {
        didSet {
            if isViewLoaded {
                pumpImageView.image = pumpImage
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pumpImageView.image = pumpImage

        self.navigationItem.hidesBackButton = true
        self.navigationItem.rightBarButtonItem = nil
    }

    override func continueButtonPressed(_ sender: Any) {
        if let setupViewController = navigationController as? MinimedPumpManagerSetupViewController {
            setupViewController.finishedSetup()
        }
    }
}
