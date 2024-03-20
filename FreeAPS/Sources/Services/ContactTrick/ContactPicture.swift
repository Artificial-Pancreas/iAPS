import Foundation
import SwiftUI

struct ContactPicture: View {
    // copy paste from watch app MainView.swift
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @Binding var contact: ContactTrickEntry
    @Binding var state: ContactTrickState

    private static let normalColorDark = Color(red: 17 / 256, green: 156 / 256, blue: 12 / 256)
    private static let normalColorLight = Color(red: 17 / 256, green: 156 / 256, blue: 12 / 256)

    private static let notUrgentColorDark = Color(red: 254 / 256, green: 149 / 256, blue: 4 / 256)
    private static let notUrgentColorLight = Color(red: 254 / 256, green: 149 / 256, blue: 4 / 256)

    private static let urgentColorDark = Color(red: 255 / 256, green: 52 / 256, blue: 0 / 256)
    private static let urgentColorLight = Color(red: 255 / 256, green: 52 / 256, blue: 0 / 256)

    private static let unknownColorDark = Color(red: 0x88 / 256, green: 0x88 / 256, blue: 0x88 / 256)
    private static let unknownColorLight = Color(red: 0x88 / 256, green: 0x88 / 256, blue: 0x88 / 256)

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        return formatter
    }()

    private static let ringWidth = 0.07 // percent
    private static let ringGap = 0.02 // percent

    static func getImage(
        contact: ContactTrickEntry,
        state: ContactTrickState
    ) -> UIImage {
        let width = 256.0
        let height = 256.0
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        let textColor: Color = contact.darkMode ?
            Color(red: 250 / 256, green: 250 / 256, blue: 250 / 256) :
            Color(red: 20 / 256, green: 20 / 256, blue: 20 / 256)
        let secondaryTextColor: Color = contact.darkMode ?
            Color(red: 200 / 256, green: 200 / 256, blue: 200 / 256) :
            Color(red: 60 / 256, green: 60 / 256, blue: 60 / 256)
        let fontWeight = contact.fontWeight.toUI()

        UIGraphicsBeginImageContext(rect.size)

        if contact.ring1 != .none {
            // offset from the white ring
            rect = CGRect(
                x: rect.minX + width * ringGap * 2,
                y: rect.minY + height * ringGap * 2,
                width: rect.width - width * ringGap * 4,
                height: rect.height - width * ringGap * 4
            )

            let ringRect = CGRect(
                x: rect.minX + width * ringGap,
                y: rect.minY + height * ringGap,
                width: rect.width - width * ringGap * 2,
                height: rect.height - width * ringGap * 2
            )
            drawRing(ring: contact.ring1, contact: contact, state: state, rect: ringRect, strokeWidth: width * ringWidth)
        }

        if contact.ring1 != .none || contact.ring2 != .none {
            rect = CGRect(
                x: rect.minX + width * (ringWidth + ringGap),
                y: rect.minY + height * (ringWidth + ringGap),
                width: rect.width - width * (ringWidth + ringGap) * 2,
                height: rect.height - height * (ringWidth + ringGap) * 2
            )
        }

        if contact.ring2 != .none {
            let ringRect = CGRect(
                x: rect.minX + width * ringGap,
                y: rect.minY + height * ringGap,
                width: rect.width - width * ringGap * 2,
                height: rect.height - width * ringGap * 2
            )
            drawRing(ring: contact.ring2, contact: contact, state: state, rect: ringRect, strokeWidth: width * ringWidth)
        }

        if contact.ring2 != .none {
            rect = CGRect(
                x: rect.minX + width * (ringWidth + ringGap),
                y: rect.minY + height * (ringWidth + ringGap),
                width: rect.width - width * (ringWidth + ringGap) * 2,
                height: rect.height - height * (ringWidth + ringGap) * 2
            )
        }

        switch contact.layout {
        case .single:
            let showTop = contact.top != .none
            let showBottom = contact.bottom != .none
            let primaryRect = (showTop || showBottom) ? CGRect(
                x: rect.minX,
                y: rect.minY + rect.height * 0.30,
                width: rect.width,
                height: rect.height * 0.40
            ) : rect
            let topRect = CGRect(
                x: rect.minX,
                y: rect.minY + rect.height * 0.07,
                width: rect.width,
                height: rect.height * 0.20
            )
            let bottomRect = CGRect(
                x: rect.minX,
                y: rect.minY + rect.height * 0.73,
                width: rect.width,
                height: rect.height * 0.20
            )
            let secondaryFontSize = Int(Double(contact.fontSize) * 0.70)

            displayPiece(
                value: contact.primary,
                contact: contact,
                state: state,
                rect: primaryRect,
                fitHeigh: false,
                fontName: contact.fontName,
                fontSize: contact.fontSize,
                fontWeight: fontWeight,
                color: textColor
            )
            if showTop {
                displayPiece(
                    value: contact.top,
                    contact: contact,
                    state: state,
                    rect: topRect,
                    fitHeigh: true,
                    fontName: contact.fontName,
                    fontSize: secondaryFontSize,
                    fontWeight: fontWeight,
                    color: secondaryTextColor
                )
            }
            if showBottom {
                displayPiece(
                    value: contact.bottom,
                    contact: contact,
                    state: state,
                    rect: bottomRect,
                    fitHeigh: true,
                    fontName: contact.fontName,
                    fontSize: secondaryFontSize,
                    fontWeight: fontWeight,
                    color: secondaryTextColor
                )
            }

        case .split:
            let topRect = CGRect(x: rect.minX, y: rect.minY + height * 0.20, width: rect.width, height: rect.height * 0.30)
            let bottomRect = CGRect(x: rect.minX, y: rect.minY + height * 0.50, width: rect.width, height: rect.height * 0.30)
            let splitFontSize = Int(Double(contact.fontSize) * 0.80)

            displayPiece(
                value: contact.top,
                contact: contact,
                state: state,
                rect: topRect,
                fitHeigh: true,
                fontName: contact.fontName,
                fontSize: splitFontSize,
                fontWeight: fontWeight,
                color: textColor
            )
            displayPiece(
                value: contact.bottom,
                contact: contact,
                state: state,
                rect: bottomRect,
                fitHeigh: true,
                fontName: contact.fontName,
                fontSize: splitFontSize,
                fontWeight: fontWeight,
                color: textColor
            )
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }

    private static func displayPiece(
        value: ContactTrickValue,
        contact: ContactTrickEntry,
        state: ContactTrickState,
        rect: CGRect,
        fitHeigh: Bool,
        fontName: String?,
        fontSize: Int,
        fontWeight: UIFont.Weight,
        color: Color
    ) {
        switch value {
        case .none:
            break
        case .glucose:
            drawText(
                text: state.glucose,
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .eventualBG:
            drawText(
                text: state.eventualBG,
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .delta:
            drawText(
                text: state.delta,
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .trend:
            drawText(
                text: state.trend,
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .glucoseDate:
            drawText(
                text: state.glucoseDate.map { formatter.string(from: $0) },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .lastLoopDate:
            drawText(
                text: state.lastLoopDate.map { formatter.string(from: $0) },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .cob:
            drawText(
                text: state.cob.map { $0.formatted() },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .iob:
            drawText(
                text: state.iob.map { $0.formatted() },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .bolusRecommended:
            drawText(
                text: state.bolusRecommended.map { $0.formatted() },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .carbsRequired:
            drawText(
                text: state.carbsRequired.map { $0.formatted() },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .isf:
            drawText(
                text: state.isf.map { $0.formatted() },
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )
        case .override:
            drawText(
                text: state.override,
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color
            )

        case .ring:
            drawRing(ring: .loop, contact: contact, state: state, rect: rect, strokeWidth: rect.width * ringWidth)
        }
    }

    private static func drawText(
        text: String?,
        rect: CGRect,
        fitHeigh: Bool,
        fontName: String?,
        fontSize: Int,
        fontWeight: UIFont.Weight,
        color: Color
    ) {
        var theFontSize = fontSize

        func makeAttributes(size: Int) -> [NSAttributedString.Key: Any] {
            let font = if let fontName {
                UIFont(name: fontName, size: CGFloat(size)) ?? UIFont.systemFont(ofSize: CGFloat(size))
            } else {
                UIFont.systemFont(ofSize: CGFloat(size), weight: fontWeight)
            }
            return [
                .font: font,
                .foregroundColor: UIColor(color)
            ]
        }

        var attributes: [NSAttributedString.Key: Any] = makeAttributes(size: theFontSize)

        if let text {
            var stringSize = text.size(withAttributes: attributes)
            while stringSize.width > rect.width * 0.90 || fitHeigh && (stringSize.height > rect.height * 0.95), theFontSize > 50 {
                theFontSize = theFontSize - 10
                attributes = makeAttributes(size: theFontSize)
                stringSize = text.size(withAttributes: attributes)
            }

            text.draw(
                in: CGRectMake(
                    rect.minX + (rect.width - stringSize.width) / 2,
                    rect.minY + (rect.height - stringSize.height) / 2,
                    rect.minX + stringSize.width,
                    rect.minY + stringSize.height
                ),
                withAttributes: attributes
            )
        }
    }

    private static func drawRing(
        ring: ContactTrickLargeRing,
        contact: ContactTrickEntry,
        state: ContactTrickState,
        rect: CGRect,
        strokeWidth: Double
    ) {
        guard let context = UIGraphicsGetCurrentContext() else {
            print("no context")
            return
        }
        switch ring {
        case .loop:
            let color = ringColor(contact: contact, state: state)

            let strokeWidth = strokeWidth
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - strokeWidth / 2

            context.setLineWidth(strokeWidth)
            context.setStrokeColor(UIColor(color).cgColor)

            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)

            context.strokePath()
        case .iob:
            if let iob = state.iob {
                drawProgressBar(
                    rect: rect,
                    progress: Double(iob) / Double(state.maxIOB),
                    colors: [contact.darkMode ? .blue : .blue, contact.darkMode ? .pink : .red],
                    strokeWidth: strokeWidth
                )
            }
        default:
            break
        }
    }

    private static func drawProgressBar(
        rect: CGRect,
        progress: Double,
        colors: [Color],
        strokeWidth: Double
    ) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - strokeWidth / 2
        let lineWidth: CGFloat = strokeWidth
        let startAngle: CGFloat = -(.pi + .pi / 4.0)
        let endAngle: CGFloat = .pi / 4.0
        let progressAngle = startAngle + (endAngle - startAngle) * max(min(progress, 1.0), 0.0)

        let colors = colors.map { c in UIColor(c).cgColor }
        let locations: [CGFloat] = [0.0, 1.0]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        ) else {
            return
        }

        context.saveGState()
        context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: progressAngle, clockwise: false)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        let segmentPath = context.path!
        context.strokePath()
        context.saveGState()
        context.addPath(segmentPath)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        context.restoreGState()
    }

    private static func ringColor(
        contact _: ContactTrickEntry,
        state: ContactTrickState
    ) -> Color {
        guard let lastLoopDate = state.lastLoopDate else {
            return .loopGray
        }
        let delta = Date().timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    var uiImage: UIImage {
        ContactPicture.getImage(contact: contact, state: state)
    }

    var body: some View {
        Image(uiImage: uiImage)
            .frame(width: 256, height: 256)
    }
}

extension FontWeight {
    func toUI() -> UIFont.Weight {
        switch self {
        case .light:
            UIFont.Weight.light
        case .regular:
            UIFont.Weight.regular
        case .medium:
            UIFont.Weight.medium
        case .semibold:
            UIFont.Weight.semibold
        case .bold:
            UIFont.Weight.bold
        case .black:
            UIFont.Weight.black
        }
    }
}

struct ContactPicturePreview: View {
    @Binding var contact: ContactTrickEntry
    @Binding var state: ContactTrickState

    var body: some View {
        ZStack {
            ContactPicture(contact: $contact, state: $state)
            Circle()
                .stroke(lineWidth: 20)
                .foregroundColor(.white)
        }
        .frame(width: 256, height: 256)
        .clipShape(Circle())
        .preferredColorScheme($contact.wrappedValue.darkMode ? .dark : .light)
    }
}

struct ContactPicture_Previews: PreviewProvider {
    struct Preview: View {
        @State var rangeIndicator: Bool = true
        @State var darkMode: Bool = true
        @State var fontSize: Int = 130
        @State var fontWeight: UIFont.Weight = .bold
        @State var fontName: String? = "AmericanTypewriter"

        var body: some View {
            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        primary: .glucose,
                        top: .delta,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    delta: "+0.2",
                    cob: 25
                ))

            ).previewDisplayName("bg + trend + delta")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        primary: .glucose,
                        top: .ring,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    lastLoopDate: .now
                ))

            ).previewDisplayName("bg + trend + ring")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .glucose,
                        top: .none,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "8.8",
                    trend: "→",
                    lastLoopDate: .now
                ))

            ).previewDisplayName("bg + trend + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .glucose,
                        top: .none,
                        bottom: .eventualBG,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    lastLoopDate: .now - 7.minutes,
                    eventualBG: "⇢ 6.2"
                ))

            ).previewDisplayName("bg + eventual + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .glucoseDate,
                        top: .none,
                        bottom: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    glucoseDate: .now - 3.minutes,
                    lastLoopDate: .now
                ))

            ).previewDisplayName("glucoseDate + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .lastLoopDate,
                        top: .none,
                        bottom: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    lastLoopDate: .now - 2.minutes
                ))

            ).previewDisplayName("lastLoopDate + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        ring2: .iob,
                        primary: .glucose,
                        top: .none,
                        bottom: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    lastLoopDate: .now,
                    iob: 6.1,
                    maxIOB: 8.0
                ))

            ).previewDisplayName("bg + ring1 + ring2")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .split,
                        top: .iob,
                        bottom: .cob,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    iob: 1.5,
                    cob: 25
                ))

            ).previewDisplayName("iob + cob")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .split,
                        top: .override,
                        bottom: .iob,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    iob: 1.5,
                    override: "75 %"
                ))

            ).previewDisplayName("overrides + iob")
        }
    }

    static var previews: some View {
        Preview()
    }
}
