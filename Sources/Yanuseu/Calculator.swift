import Foundation

enum CalculatorError: Error, Equatable {
    case expressionTooLong
    case invalidExpression
    case divisionByZero
    case nonFiniteResult
}

enum Calculator {
    static func evaluate(_ expression: String) throws -> Double {
        guard expression.utf8.count <= 256 else { throw CalculatorError.expressionTooLong }
        var parser = Parser(bytes: Array(expression.utf8))
        return try parser.parse()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func parse() throws -> Double {
            let result = try parseExpression()
            skipWhitespace()
            guard index == bytes.count else { throw CalculatorError.invalidExpression }
            return try finite(result)
        }

        private mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                skipWhitespace()
                if consume(43) { value = try finite(value + parseTerm()) }
                else if consume(45) { value = try finite(value - parseTerm()) }
                else { return value }
            }
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while true {
                skipWhitespace()
                if consume(42) { value = try finite(value * parseUnary()) }
                else if consume(47) {
                    let divisor = try parseUnary()
                    guard divisor != 0 else { throw CalculatorError.divisionByZero }
                    value = try finite(value / divisor)
                } else { return value }
            }
        }

        private mutating func parseUnary() throws -> Double {
            skipWhitespace()
            if consume(43) { return try parseUnary() }
            if consume(45) { return try finite(-(try parseUnary())) }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            if consume(40) {
                let value = try parseExpression()
                skipWhitespace()
                guard consume(41) else { throw CalculatorError.invalidExpression }
                return value
            }
            return try parseNumber()
        }

        private mutating func parseNumber() throws -> Double {
            let start = index
            var digitCount = 0
            while index < bytes.count, isDigit(bytes[index]) {
                digitCount += 1
                index += 1
            }
            if index < bytes.count, bytes[index] == 46 {
                index += 1
                while index < bytes.count, isDigit(bytes[index]) {
                    digitCount += 1
                    index += 1
                }
            }
            guard digitCount > 0,
                  let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw CalculatorError.invalidExpression
            }
            return try finite(number)
        }

        private mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 9, 10, 13, 32: index += 1
                default: return
                }
            }
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        private func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }

        private func finite(_ value: Double) throws -> Double {
            guard value.isFinite else { throw CalculatorError.nonFiniteResult }
            return value
        }
    }
}
