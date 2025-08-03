import SwiftUI

struct DynamicHistoryView: View {
    let units: GlucoseUnits

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

    private var tddFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 1
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
            Text("History").padding(.bottom, 20).font(.system(size: 26))
            // SubTitle
            HStack {
                Spacer()
                Text("Insulin").foregroundStyle(Color(.insulin))
            }.font(.system(size: 18)).padding(.bottom, 5).padding(.horizontal, 20)

            Divider()

            // Subtitle with non-localized variable acronyms
            ZStack {
                HStack(spacing: 15) {
                    Text(verbatim: "Time").foregroundStyle(.primary)
                    Text(verbatim: "BG").foregroundStyle(Color(.loopGreen))
                    Text(verbatim: "TDD").foregroundStyle(Color(.basal))
                    Text(verbatim: "Ratio").foregroundStyle(.red)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20)
                HStack(spacing: 20) {
                    Text(verbatim: "ISF").foregroundStyle(.orange)
                    Text(verbatim: "CR ").foregroundStyle(.orange)
                }.frame(maxWidth: .infinity, alignment: .center).offset(x: 22)
                HStack(spacing: 20) {
                    Text(verbatim: "Req.").foregroundColor(.secondary)
                    Text(verbatim: "TBR").foregroundColor(.blue)
                    Text(verbatim: "SMB").foregroundColor(.blue)
                }.frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
            }.font(.system(size: 12)).padding(.vertical, 4)

            Divider()

            // Non-localized data table
            List {
                ForEach(reasons) { item in
                    if let glucose = item.glucose, glucose != 0, let isf = item.isf, let cr = item.cr {
                        // Prepare an array of Strings
                        let converted = units == .mmolL ? (glucose as Decimal)
                            .asMmolL : (glucose as Decimal)
                        let dynamicReasons = [
                            glucoseFormatter.string(from: isf as NSNumber) ?? "",
                            glucoseFormatter.string(from: cr as NSNumber) ?? "",
                            (item.tdd ?? 0) != 0 ? (tddFormatter.string(from: (item.tdd ?? 0) as NSNumber) ?? "") : "--"
                        ]

                        Grid(horizontalSpacing: 0) {
                            GridRow {
                                // Time
                                Text(dateFormatter.string(from: item.date ?? Date()))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                // Glucose
                                Text(glucoseFormatter.string(from: converted as NSNumber) ?? "")
                                    .foregroundStyle(Color(.loopGreen))
                                    .frame(maxWidth: .infinity, alignment: .leading).offset(x: 5)
                                // TDD
                                Text(dynamicReasons[2])
                                    .foregroundStyle(Color(.basal))
                                    .frame(maxWidth: .infinity, alignment: .leading).offset(x: -1)
                                // Ratio
                                Text(formatter.string(from: item.ratio ?? 1) ?? "").foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                // ISF.
                                Text(dynamicReasons.first ?? "")
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                // CR
                                Text(dynamicReasons[1])
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                // Insunlin Required
                                let insReqString = reqFormatter.string(from: (item.insulinReq ?? 0) as NSNumber) ?? ""
                                Text(insReqString != "0.00" ? insReqString : "0  ")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                // Basal Rate
                                Text(formatter.string(from: (item.rate ?? 0) as NSNumber) ?? "")
                                    .foregroundColor(Color(.insulin))
                                    .frame(maxWidth: .infinity, alignment: .trailing).offset(x: 5)
                                // SMBs
                                Text(
                                    (item.smb ?? 0) != 0 ?
                                        "\(formatter.string(from: (item.smb ?? 0) as NSNumber) ?? "")"
                                        : "   "
                                ).foregroundColor(Color(.insulin))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }.listRowBackground(item.override ? Color.purpleOverrides : nil)
                    }
                }
            }.font(.system(size: 12)).listStyle(.plain)
        }.background(Color(.systemGray5))
    }
}
