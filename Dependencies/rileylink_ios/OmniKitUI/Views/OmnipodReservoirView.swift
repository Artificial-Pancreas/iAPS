//
//  OmnipodReservoirView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/22/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import LoopKitUI
import OmniKit

public final class OmnipodReservoirView: LevelHUDView, NibLoadable {
    
    override public var orderPriority: HUDViewOrderPriority {
        return 11
    }

    @IBOutlet private weak var volumeLabel: UILabel!
    
    @IBOutlet private weak var alertLabel: UILabel! {
        didSet {
            alertLabel.alpha = 0
            alertLabel.textColor = UIColor.white
            alertLabel.layer.cornerRadius = 9
            alertLabel.clipsToBounds = true
        }
    }

    public class func instantiate() -> OmnipodReservoirView {
        return nib().instantiate(withOwner: nil, options: nil)[0] as! OmnipodReservoirView
    }

    override public func awakeFromNib() {
        super.awakeFromNib()

        volumeLabel.isHidden = true
    }

    private var reservoirLevel: ReservoirLevel?
    private var lastUpdateDate: Date?
    private var reservoirLevelHighlightState = ReservoirLevelHighlightState.normal

    override public func tintColorDidChange() {
        super.tintColorDidChange()
        
        alertLabel?.backgroundColor = tintColor
        volumeLabel.textColor = tintColor
        levelMaskView.tintColor = tintColor
    }

    override public func updateColor() {
        switch reservoirLevelHighlightState {
        case .normal:
            tintColor = stateColors?.normal
        case .warning:
            tintColor = stateColors?.warning
        case .critical:
            tintColor = stateColors?.error
        }
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

            let time = timeFormatter.string(from: date)
            caption?.text = time

            switch reservoirLevel {
            case .aboveThreshold:
                level = nil
                volumeLabel.isHidden = true
                if let units = numberFormatter.string(from: Pod.maximumReservoirReading) {
                    volumeLabel.text = String(format: LocalizedString("%@+ U", comment: "Format string for reservoir volume when above maximum reading. (1: The maximum reading)"), units)
                    accessibilityValue = String(format: LocalizedString("Greater than %1$@ units remaining at %2$@", comment: "Accessibility format string for (1: localized volume)(2: time)"), units, time)
                }
            case .valid(let value):
                level = reservoirLevel.percentage
                volumeLabel.isHidden = false

                if let units = numberFormatter.string(from: value) {
                    volumeLabel.text = String(format: LocalizedString("%@U", comment: "Format string for reservoir volume. (1: The localized volume)"), units)

                    accessibilityValue = String(format: LocalizedString("%1$@ units remaining at %2$@", comment: "Accessibility format string for (1: localized volume)(2: time)"), units, time)
                }
            }
        } else {
            level = 0
            volumeLabel.isHidden = true
        }

        var alertLabelAlpha: CGFloat = 1
        switch reservoirLevelHighlightState {
        case .normal:
            alertLabelAlpha = 0
        case .warning, .critical:
            alertLabel?.text = "!"
        }

        UIView.animate(withDuration: 0.25, animations: {
            self.alertLabel?.alpha = alertLabelAlpha
        })
    }
    
    public func update(level: ReservoirLevel?, at date: Date, reservoirLevelHighlightState: ReservoirLevelHighlightState) {
        self.reservoirLevel = level
        self.lastUpdateDate = date
        self.reservoirLevelHighlightState = reservoirLevelHighlightState
        updateViews()
    }
}
