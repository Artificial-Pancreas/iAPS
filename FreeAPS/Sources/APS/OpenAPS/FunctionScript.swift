import Foundation

struct FunctionScript {
    let name: String
    let function: String
    let variable: String
    private var source: String?

    init(name: String, function: String) {
        self.name = name
        self.function = function
        variable = function
    }

    init(name: String, function: String, variable: String) {
        self.name = name
        self.function = function
        self.variable = variable
    }

    init(name: String, for scripts: [Script], function: String, variable: String) {
        self.name = name
        self.function = function
        self.variable = variable

        let source = scripts.reduce(into: "") { source, script in
            source = "\(source)\n\(script.body)"
        }

        self.source = """
        var \(variable) = (function() {
            \(source)

            return \(function);
        })();
        """
    }

    var body: String {
        if let source = source {
            return source
        }

        let script = try! String(contentsOf: Bundle.main.url(forResource: "javascript/\(name)", withExtension: "")!)

        return """
        var \(variable) = (function() {
            \(script)

            return \(function);
        })();
        """
    }
}
