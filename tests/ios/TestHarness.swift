import Foundation

public struct TestFailure: Sendable {
    public let testName: String
    public let message: String
    public let file: String
    public let line: Int
}

public struct TestSuiteResult: Sendable {
    public let suiteName: String
    public let passed: Int
    public let failed: Int
    public let failures: [TestFailure]
    public let duration: TimeInterval
    
    public var total: Int { passed + failed }
    public var isSuccess: Bool { failed == 0 }
}

public struct TestAssertionError: Error, CustomStringConvertible {
    public let message: String
    public let file: String
    public let line: Int
    
    public var description: String {
        return "\(message) at \(file):\(line)"
    }
}

public func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if actual != expected {
        let msg = message.isEmpty ? "Expected '\(expected)', but got '\(actual)'" : "\(message) (Expected '\(expected)', got '\(actual)')"
        throw TestAssertionError(message: msg, file: file, line: line)
    }
}

public func assertAlmostEqual(_ actual: Double, _ expected: Double, accuracy: Double = 0.001, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if abs(actual - expected) > accuracy {
        let msg = message.isEmpty ? "Expected '\(expected)' (±\(accuracy)), but got '\(actual)'" : "\(message) (Expected '\(expected)', got '\(actual)')"
        throw TestAssertionError(message: msg, file: file, line: line)
    }
}

public func assertTrue(_ condition: Bool, _ message: String = "Condition is false", file: String = #file, line: Int = #line) throws {
    if !condition {
        throw TestAssertionError(message: message, file: file, line: line)
    }
}

public func assertFalse(_ condition: Bool, _ message: String = "Condition is true", file: String = #file, line: Int = #line) throws {
    if condition {
        throw TestAssertionError(message: message, file: file, line: line)
    }
}

public func assertNil<T>(_ value: T?, _ message: String = "Expected nil", file: String = #file, line: Int = #line) throws {
    if let value = value {
        throw TestAssertionError(message: "\(message) (found: \(value))", file: file, line: line)
    }
}

public func assertNotNil<T>(_ value: T?, _ message: String = "Expected non-nil value", file: String = #file, line: Int = #line) throws {
    if value == nil {
        throw TestAssertionError(message: message, file: file, line: line)
    }
}
