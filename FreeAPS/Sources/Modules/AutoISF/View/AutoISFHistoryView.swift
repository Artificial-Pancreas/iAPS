import SwiftUI

struct AutoISFHistoryView: View {
    let units: GlucoseUnits
    let device = UIDevice.current.getDeviceId

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        entity: Reasons.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
        predicate: NSPredicate(format: "date > %@", DateFilter().day)
    ) var reasons: FetchedResults<Reasons>

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        return formatter
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        if units == .mmolL {
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 1
        } else {
            formatter.maximumFractionDigits = 0
        }
        return formatter
    }

    private var reqFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        history
    }

    private var history: some View {
        VStack(spacing: 0) {
            Button { dismiss() }
            label: {
                HStack {
                    Image(systemName: "chevron.backward").font(.system(size: 22))
                    Text("Back").font(.system(size: 18))
                }
            }
            .tint(.blue).buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            // Title
            Text("History")
                .padding(.bottom, 20)
                .font(.system(size: 26))
            // SubTitle
            HStack {
                Text("Final Ratio").foregroundStyle(.red)
                Spacer()
                Text("Adjustments").foregroundStyle(.orange).offset(x: -20)
                Spacer()
                Text("Insulin").foregroundStyle(Color(.insulin))
            }
            .font(.system(size: 18))
            .padding(.bottom, 5)
            .padding(.horizontal, 20)

            Divider()

            let proMaxOffset_1: CGFloat = (device == "iPhone17,2" || device == "iPhone 15 Pro Max") ? -21 : -9
            let proMaxOffset_2: CGFloat = (device == "iPhone17,2" || device == "iPhone 15 Pro Max") ? -10 : 0

            // Subtitle with non-localized variable acronyms
            HStack(spacing: 10) {
                Text(verbatim: "Time").foregroundStyle(.primary)
                Spacer(minLength: 1)
                Text(verbatim: "BG  ").foregroundStyle(Color(.loopGreen)).offset(x: proMaxOffset_1)
                Text(verbatim: "Final").foregroundStyle(.red).offset(x: proMaxOffset_1)
                Text(verbatim: "acce").foregroundStyle(.orange).offset(x: 2 + proMaxOffset_2)
                Text(verbatim: "bg  ").foregroundStyle(.orange).offset(x: 6 + proMaxOffset_2)
                Text(verbatim: "dura  ").foregroundStyle(.orange).offset(x: 6)
                Text(verbatim: "pp  ").foregroundStyle(.orange).offset(x: 4)
                Spacer(minLength: 3)
                Text(verbatim: "Req. ").foregroundColor(.secondary).offset(x: proMaxOffset_2 / 2)
                Text(verbatim: "TBR ").foregroundColor(.blue).offset(x: proMaxOffset_2 / 2)
                Text(verbatim: "SMB ").foregroundColor(.blue).offset(x: proMaxOffset_2 / 2)
            }
            .padding(.horizontal, 5)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Divider()

            // Non-localized data table
            List {
                ForEach(reasons) { item in
                    if let glucose = item.glucose, glucose != 0, let aisf_reaons = item.reasons {
                        // Prepare an array of Strings
                        let reasonParsed = aisf_reaons.string.components(separatedBy: ",")
                            .filter({ $0 != "B30 Active" }).map(
                                { item in
                                    let check = item.components(separatedBy: ":").last ?? ""
                                    return check == " 1" ? " -- " : check
                                }
                            )
                        let converted = units == .mmolL ? (glucose as Decimal)
                            .asMmolL : (glucose as Decimal)
                        if reasonParsed.count >= 4 {
                            Grid(horizontalSpacing: 0) {
                                GridRow {
                                    // Time
                                    Text(dateFormatter.string(from: item.date ?? Date()))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 7)
                                    Spacer(minLength: 5)
                                    // Glucose
                                    Text(glucoseFormatter.string(from: converted as NSNumber) ?? "")
                                        .foregroundStyle(Color(.loopGreen))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 4)
                                    // Ratio
                                    Text((formatter.string(from: item.ratio ?? 1) ?? "") + "  ").foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    // acce.
                                    Text((reasonParsed.first ?? "") + "  ")
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 5)
                                    // bg
                                    Text(reasonParsed[1] + "  ")
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 8)
                                    // dura
                                    Text(reasonParsed[2] + "  ")
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 5)
                                    // pp
                                    Text(reasonParsed[3] + "  ")
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 3)
                                    Spacer(minLength: 13)
                                    // Insunlin Required
                                    let insReqString = reqFormatter.string(from: (item.insulinReq ?? 0) as NSNumber) ?? ""
                                    Text(insReqString != "0.00" ? insReqString + " " : "0  ")
                                        .offset(x: -1 * proMaxOffset_2)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer(minLength: 2)
                                    // Basal Rate
                                    Text((formatter.string(from: (item.rate ?? 0) as NSNumber) ?? "") + " ")
                                        .offset(x: -1 * proMaxOffset_2)
                                        .foregroundColor(Color(.insulin))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    // SMBs
                                    Text(
                                        (item.smb ?? 0) != 0 ?
                                            "\(formatter.string(from: (item.smb ?? 0) as NSNumber) ?? "")  "
                                            : "   "
                                    )
                                    .offset(x: -1 * proMaxOffset_2)
                                    .foregroundColor(Color(.insulin))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(colorScheme == .dark ? Color(.black) : Color(.white))
            }
            .font(.system(size: 12))
            .listStyle(.plain)
        }
        .background(Color(.systemGray6).opacity(colorScheme == .dark ? 1 : 0.7))
    }
}
