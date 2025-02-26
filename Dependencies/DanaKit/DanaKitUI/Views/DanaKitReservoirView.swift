//
//  DanaKitReservoirView.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 18/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import UIKit
import LoopKitUI

public final class DanaKitReservoirView: LevelHUDView, NibLoadable {
    override public var orderPriority: HUDViewOrderPriority {
        return 11
    }
    
    @IBOutlet private weak var volumeLabel: UILabel!
    
    private var reservoirLevel: Double?
    private var lastUpdateDate: Date?
    
    public class func instantiate() -> DanaKitReservoirView {
        return nib().instantiate(withOwner: nil, options: nil)[0] as! DanaKitReservoirView
    }

    override public func awakeFromNib() {
        super.awakeFromNib()

        volumeLabel.isHidden = true
    }
    
    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0

        return formatter
    }()
    
    private func updateViews() {
        if let reservoirLevel = reservoirLevel, let date = lastUpdateDate {
            level = reservoirLevel / 300
            let units = NSString(format: "%.0f", reservoirLevel)

            let time = timeFormatter.string(from: date)
            caption?.text = time
            
            volumeLabel.isHidden = false
            volumeLabel.text = String(format: LocalizedString("%@U", comment: "Format string for reservoir volume. (1: The localized volume)"), units)

            accessibilityValue = String(format: LocalizedString("%1$@ units remaining at %2$@", comment: "Accessibility format string for (1: localized volume)(2: time)"), units, time)
        } else {
            level = 0
            volumeLabel.isHidden = true
        }
    }
    
    public func update(level: Double?, at date: Date) {
        self.reservoirLevel = level
        self.lastUpdateDate = date
        updateViews()
    }
    
}
