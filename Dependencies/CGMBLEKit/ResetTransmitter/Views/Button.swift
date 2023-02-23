//
//  Button.swift
//  ResetTransmitter
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit


class Button: UIButton {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        backgroundColor = tintColor
        layer.cornerRadius = 6

        titleLabel?.adjustsFontForContentSizeCategory = true
        contentEdgeInsets.top = 14
        contentEdgeInsets.bottom = 14
        setTitleColor(.white, for: .normal)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        backgroundColor = tintColor
    }

    override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()

        tintColor = .blue
        tintColorDidChange()
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : 1
        }
    }

    override var isEnabled: Bool {
        didSet {
            tintAdjustmentMode = isEnabled ? .automatic : .dimmed
        }
    }
}
