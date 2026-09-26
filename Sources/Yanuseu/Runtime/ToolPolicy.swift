import Foundation

enum ToolCapability: String, CaseIterable, Codable, Hashable {
    case calculator
}

struct ToolPolicy: Equatable {
    var allowed: Set<ToolCapability> = []

    init(allowed: Set<ToolCapability> = []) { self.allowed = allowed }
    init(calculatorEnabled: Bool) { allowed = calculatorEnabled ? [.calculator] : [] }
    func allows(_ capability: ToolCapability) -> Bool { allowed.contains(capability) }
}

struct NativeToolDescription: Identifiable {
    let capability: ToolCapability
    let title: String
    let summary: String
    var id: ToolCapability { capability }
}

enum ToolRegistry {
    static let descriptions: [NativeToolDescription] = [
        .init(capability: .calculator, title: "Calculator", summary: "Evaluate basic arithmetic on this iPhone. No network, files, or other apps.")
    ]

    static func schemas(for policy: ToolPolicy) -> [[String: Any]] {
        ToolCapability.allCases.filter { policy.allows($0) }.map { capability in
            switch capability {
            case .calculator:
                return [
                    "type": "function",
                    "function": [
                        "name": capability.rawValue,
                        "description": "Evaluate a basic arithmetic expression. Supports numbers, parentheses, +, -, *, and /.",
                        "parameters": [
                            "type": "object",
                            "properties": ["expression": ["type": "string", "description": "Arithmetic expression only"]],
                            "required": ["expression"],
                            "additionalProperties": false
                        ]
                    ]
                ]
            }
        }
    }
}
