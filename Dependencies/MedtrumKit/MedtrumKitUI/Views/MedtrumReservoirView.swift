import LoopKitUI
import UIKit

public final class MedtrumReservoirView: LevelHUDView, NibLoadable {
    override public var orderPriority: HUDViewOrderPriority {
        11
    }

    @IBOutlet private var volumeLabel: UILabel!

    private var maxReservoirLevel: Double = 200
    private var reservoirLevel: Double?
    private var lastUpdateDate: Date?

    public class func instantiate() -> MedtrumReservoirView {
        nib().instantiate(withOwner: nil, options: nil)[0] as! MedtrumReservoirView
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
            level = reservoirLevel / maxReservoirLevel
            let units = NSString(format: "%.0f", reservoirLevel)

            let time = timeFormatter.string(from: date)
            caption?.text = time

            volumeLabel.isHidden = false
            volumeLabel.text = String(
                format: LocalizedString("%@U", comment: "Format string for reservoir volume. (1: The localized volume)"),
                units
            )

            accessibilityValue = String(
                format: LocalizedString(
                    "%1$@ units remaining at %2$@",
                    comment: "Accessibility format string for (1: localized volume)(2: time)"
                ),
                units,
                time
            )
        } else {
            level = 0
            volumeLabel.isHidden = true
        }
    }

    public func update(level: Double, at date: Date, max maxReservoirLevel: Double) {
        reservoirLevel = level
        lastUpdateDate = date
        self.maxReservoirLevel = maxReservoirLevel
        updateViews()
    }
}
