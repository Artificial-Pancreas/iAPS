extension Array where Element: Hashable {
    func removeDublicates() -> Self {
        var result = Self()
        for item in self {
            if !result.contains(item) {
                result.append(item)
            }
        }
        return result
    }
}

extension Collection {
    /**
     Returns the most frequent element in the collection.
     */
    func mostFrequent() -> Element? where Element: Hashable {
        reduce(into: [:]) { $0[$1, default: 0] += 1 }.max(by: { $0.1 < $1.1 })?.key
    }
}
