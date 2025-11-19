import SwiftUI
import UIKit

extension Color {
    static let carbs = Color("carbs")

    static let fresh = Color("fresh")

    static let glucose = Color("glucose")

    // The loopAccent color is intended to be use as the app accent color.
    public static let loopAccent = Color("accent")
}

// Color version of the UIColor context colors
public extension Color {
    static let agingColor = warning

    static let axisLabelColor = secondary

    static let axisLineColor = clear

    #if os(iOS)
        static let cellBackgroundColor = Color(UIColor.cellBackgroundColor)
        static let gridColor = Color(UIColor.gridColor)
        static let unknownColor = Color(UIColor.unknownColor)
    #endif

    static let carbTintColor = carbs

    static let critical = red

    static let destructive = critical

    static let glucoseTintColor = glucose

    static let invalid = critical

    static let insulinTintColor = insulin

    static let pumpStatusNormal = insulin

    static let staleColor = critical
}

extension Color {
    static let loopManualTemp = Color("ManualTempBasal")
    //   static let insulin = Color("Insulin")
    static let uam = Color("UAM")
    static let zt = Color("ZT")
    static let blueComplicationBackground = Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196)
    static let homeBackground = Color("HomeBackground")
    static let darkChartBackground = Color("DarkChartBackground")
}
