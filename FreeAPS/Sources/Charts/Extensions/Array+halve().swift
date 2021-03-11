import Foundation

extension Array {
    func halve() -> [[Element]] {
        let half = count / 2
        let leftSplit = self[0 ..< half]
        let rightSplit = self[half...]
        return [Array(leftSplit), Array(rightSplit)]
    }
}
