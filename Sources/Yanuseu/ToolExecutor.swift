import Foundation

enum ToolExecutor {
    static func execute(_ call: ToolCall) -> String {
        guard call.function.arguments.utf8.count <= 1_024 else {
            return "Calculator arguments were too large; no calculation was run."
        }
        guard call.function.name == "calculator" else {
            return "That tool is unavailable; no action was taken."
        }
        guard let data = call.function.arguments.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expression = arguments["expression"] as? String else {
            return "The calculator requires a JSON string field named expression."
        }
        do {
            let result = try Calculator.evaluate(expression)
            return String(format: "%.10g", result)
        } catch {
            return "The calculator rejected that expression."
        }
    }
}
