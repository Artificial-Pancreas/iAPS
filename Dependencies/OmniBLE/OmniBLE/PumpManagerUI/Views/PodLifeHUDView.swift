//
//  PodLifeHUDView.swift
//  OmniBLE
//
//  Based on OmniKitUI/Views/PodLifeHUDView.swift
//  Created by Pete Schwamb on 10/22/18.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI
import MKRingProgressView

public enum PodAlertState {
    case none
    case warning
    case fault
}

public class PodLifeHUDView: BaseHUDView, NibLoadable {

    override public var orderPriority: HUDViewOrderPriority {
        return 12
    }

    @IBOutlet private weak var timeLabel: UILabel! {
        didSet {
            // Setting this color in code because the nib isn't being applied correctly
            if #available(iOSApplicationExtension 13.0, *) {
                timeLabel.textColor = .label
            }
        }
    }
    @IBOutlet private weak var progressRing: RingProgressView!
    
    @IBOutlet private weak var alertLabel: UILabel! {
        didSet {
            alertLabel.alpha = 0
            alertLabel.textColor = UIColor.white
            alertLabel.layer.cornerRadius = 9
            alertLabel.clipsToBounds = true
        }
    }
    @IBOutlet private weak var backgroundRing: UIImageView! {
        didSet {
            if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
                backgroundRing.tintColor = .systemGray5
            } else {
                backgroundRing.tintColor = UIColor(red: 198 / 255, green: 199 / 255, blue: 201 / 255, alpha: 1)
            }
        }
    }

    private var startTime: Date?
    private var lifetime: TimeInterval?
    private var timer: Timer?
    
    public var alertState: PodAlertState = .none {
        didSet {
            updateAlertStateLabel()
        }
    }

    public class func instantiate() -> PodLifeHUDView {
        return nib().instantiate(withOwner: nil, options: nil)[0] as! PodLifeHUDView
    }
    
    public func setPodLifeCycle(startTime: Date, lifetime: TimeInterval) {
        self.startTime = startTime
        self.lifetime = lifetime
        updateProgressCircle()

        if timer == nil {
            self.timer = Timer.scheduledTimer(withTimeInterval: .seconds(10), repeats: true) { [weak self] _ in
                self?.updateProgressCircle()
            }
        }
    }
    
    override open func stateColorsDidUpdate() {
        super.stateColorsDidUpdate()
        updateProgressCircle()
        updateAlertStateLabel()
    }
    
    private var endColor: UIColor? {
        didSet {
            let primaryColor = endColor ?? UIColor(red: 198 / 255, green: 199 / 255, blue: 201 / 255, alpha: 1)
            self.progressRing.endColor = primaryColor
            self.progressRing.startColor = primaryColor
        }
    }
    
    private lazy var timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .abbreviated
        
        return formatter
    }()

    private func updateAlertStateLabel() {
        var alertLabelAlpha: CGFloat = 1
        
        if alertState == .fault {
            timer = nil
        }
        
        switch alertState {
        case .fault:
            alertLabel.text = "!"
            alertLabel.backgroundColor = stateColors?.error
        case .warning:
            alertLabel.text = "!"
            alertLabel.backgroundColor = stateColors?.warning
        case .none:
            alertLabelAlpha = 0
        }
        alertLabel.alpha = alertLabelAlpha
        UIView.animate(withDuration: 0.25, animations: {
            self.alertLabel.alpha = alertLabelAlpha
        })
    }
    
    private func updateProgressCircle() {
        
        if let startTime = startTime, let lifetime = lifetime {
            let age = -startTime.timeIntervalSinceNow
            let progress = Double(age / lifetime)
            progressRing.progress = progress
            
            if progress < 0.75 {
                self.endColor = stateColors?.normal
                progressRing.shadowOpacity = 0
            } else if progress < 1.0 {
                self.endColor = stateColors?.warning
                progressRing.shadowOpacity = 0.5
            } else {
                self.endColor = stateColors?.error
                progressRing.shadowOpacity = 0.8
            }
            
            let remaining = (lifetime - age)

            // Update time label and caption
            if alertState == .fault {
                timeLabel.isHidden = true
                caption.text = LocalizedString("Fault", comment: "Pod life HUD view label")
            } else if remaining > .hours(24) {
                timeLabel.isHidden = true
                caption.text = LocalizedString("Pod Age", comment: "Label describing pod age view")
            } else if remaining > 0 {
                let remainingFlooredToHour = remaining > .hours(1) ? remaining - remaining.truncatingRemainder(dividingBy: .hours(1)) : remaining
                if let timeString = timeFormatter.string(from: remainingFlooredToHour) {
                    timeLabel.isHidden = false
                    timeLabel.text = timeString
                }
                caption.text = LocalizedString("Remaining", comment: "Label describing time remaining view")
            } else {
                timeLabel.isHidden = true
                caption.text = LocalizedString("Replace Pod", comment: "Label indicating pod replacement necessary")
            }
        }
    }

    func pauseUpdates() {
        timer?.invalidate()
        timer = nil
    }

    override public func awakeFromNib() {
        super.awakeFromNib()
    }
}
