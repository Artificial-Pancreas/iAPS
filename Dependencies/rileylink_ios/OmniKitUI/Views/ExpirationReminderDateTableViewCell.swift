//
//  ExpirationReminderDateTableViewCell.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 4/11/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKitUI

public class ExpirationReminderDateTableViewCell: DatePickerTableViewCell {

    public weak var delegate: DatePickerTableViewCellDelegate?

    @IBOutlet public weak var titleLabel: UILabel! {
        didSet {
            // Setting this color in code because the nib isn't being applied correctly
            if #available(iOSApplicationExtension 13.0, *) {
                titleLabel?.textColor = .label
            }
        }
    }

    @IBOutlet public weak var dateLabel: UILabel! {
        didSet {
            // Setting this color in code because the nib isn't being applied correctly
            if #available(iOSApplicationExtension 13.0, *) {
                dateLabel?.textColor = .secondaryLabel
            }

            switch effectiveUserInterfaceLayoutDirection {
            case .leftToRight:
                dateLabel?.textAlignment = .right
            case .rightToLeft:
                dateLabel?.textAlignment = .left
            @unknown default:
                dateLabel?.textAlignment = .right
            }
        }
    }

    var maximumDate: Date? {
        set {
            datePicker.maximumDate = newValue
        }
        get {
            return datePicker.maximumDate
        }
    }

    var minimumDate: Date? {
        set {
            datePicker.minimumDate = newValue
        }
        get {
            return datePicker.minimumDate
        }
    }

    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        formatter.doesRelativeDateFormatting = true

        return formatter
    }()

    public override func updateDateLabel() {
        dateLabel.text = formatter.string(from: date)
    }

    public override func dateChanged(_ sender: UIDatePicker) {
        super.dateChanged(sender)

        delegate?.datePickerTableViewCellDidUpdateDate(self)
    }
}

extension ExpirationReminderDateTableViewCell: NibLoadable { }
