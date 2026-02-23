import XCTest

/// Deep regression tests that verify SonarQube code quality rules are not violated.
/// These tests scan Swift source files to catch violations before they reach SonarQube.
final class SonarQubeRulesTests: XCTestCase {

    // MARK: - Paths

    private var sourceRoot: URL {
        // VaultTests is in apps/ios/VaultTests, source is in apps/ios/Vault
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VaultTests/
            .appendingPathComponent("../Vault", isDirectory: true)
            .standardized
    }

    private var testRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VaultTests/
            .standardized
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }
        return files
    }

    // MARK: - S1186: Empty Closures and Functions

    /// Verifies no empty closure/function bodies exist without a // comment.
    /// SonarQube requires at least a line comment explaining why the body is empty.
    func testS1186_NoEmptyClosureBodiesWithoutComment() throws {
        let files = swiftFiles(in: sourceRoot) + swiftFiles(in: testRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        for fileURL in files {
            // Skip this test file to avoid self-referential matches
            if fileURL.lastPathComponent == "SonarQubeRulesTests.swift" { continue }

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip lines that are comments themselves
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                // Pattern: `{ }` or `{}` at end of line (empty body on one line)
                // But allow `{ }` in struct/enum declarations and protocol conformance
                if trimmed.hasSuffix("{ }") || trimmed.hasSuffix("{}") {
                    // Allow: `extension Foo: Bar {}`, `struct Foo {}`, `enum Foo {}`
                    if trimmed.contains("extension ") || trimmed.contains("struct ") ||
                       trimmed.contains("enum ") || trimmed.contains("class ") ||
                       trimmed.contains("protocol ") { continue }
                    violations.append((relativePath, index + 1, trimmed))
                }

                // Pattern: `{ /* ... */ }` (inline block comment instead of // comment)
                if trimmed.contains("{ /*") && trimmed.contains("*/ }") {
                    violations.append((relativePath, index + 1, trimmed))
                }

                // Pattern: `{ _ in }` (empty closure with parameter)
                if trimmed.hasSuffix("{ _ in }") || trimmed.hasSuffix("{ _ in}") {
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S1186: Found \(violations.count) empty closure/function bodies without // comments:\n\(report)")
        }
    }

    // MARK: - S3358: Nested Ternary Operations

    /// Verifies no nested ternary expressions exist in production code.
    func testS3358_NoNestedTernaryOperations() throws {
        let files = swiftFiles(in: sourceRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        for fileURL in files {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip comments
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                // Count ternary operators on a single line
                // A nested ternary has 2+ `?` operators that are ternary (not optional chaining)
                // Simple heuristic: look for `? ... : ... ? ... :` pattern
                let components = trimmed.components(separatedBy: " ? ")
                if components.count >= 3 {
                    // Likely a nested ternary
                    // Verify it's not just optional chaining by checking for `:`
                    let colonCount = trimmed.filter { $0 == ":" }.count
                    // A nested ternary needs at least 2 colons as part of ternary operators
                    if colonCount >= 2 {
                        violations.append((relativePath, index + 1, trimmed))
                    }
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S3358: Found \(violations.count) nested ternary operations:\n\(report)")
        }
    }

    // MARK: - S3661: No try! in Tests

    /// Verifies test files don't use `try!` (should use `try` with throwing test functions).
    func testS3661_NoForceTriesInTests() throws {
        let files = swiftFiles(in: testRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        for fileURL in files {
            // Skip this test file itself
            if fileURL.lastPathComponent == "SonarQubeRulesTests.swift" { continue }

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip comments
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                if trimmed.contains("try!") {
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S3661: Found \(violations.count) `try!` usages in test files (use `try` with throwing test functions instead):\n\(report)")
        }
    }

    // MARK: - S100/S117: Naming Conventions

    /// Verifies no underscore-prefixed function or property names in production code.
    func testS100_S117_NoUnderscorePrefixedNames() throws {
        let files = swiftFiles(in: sourceRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        let underscoreFuncPattern = try NSRegularExpression(
            pattern: #"(?:private |internal |public |open |fileprivate )?func _[a-zA-Z]"#
        )
        let underscoreVarPattern = try NSRegularExpression(
            pattern: #"(?:private |internal |public |open |fileprivate )?(?:let|var) _[a-zA-Z]"#
        )

        for fileURL in files {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip comments
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                let range = NSRange(trimmed.startIndex..., in: trimmed)

                if underscoreFuncPattern.firstMatch(in: trimmed, range: range) != nil {
                    violations.append((relativePath, index + 1, trimmed))
                }

                if underscoreVarPattern.firstMatch(in: trimmed, range: range) != nil {
                    // Allow `_currentIndex` style SwiftUI property wrapper access - they appear in assignments
                    // Only flag declarations (let/var)
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S100/S117: Found \(violations.count) underscore-prefixed function/property names:\n\(report)")
        }
    }

    // MARK: - S1172: Unused Parameters

    /// Verifies no `_paramName` pattern in function signatures (should use bare `_`).
    func testS1172_NoUnderscorePrefixedParameters() throws {
        let files = swiftFiles(in: sourceRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        // Pattern: `_ _someVar:` in function parameters (underscore external + underscore-prefixed internal)
        let pattern = try NSRegularExpression(
            pattern: #"_ _[a-zA-Z]+\s*:"#
        )

        for fileURL in files {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip comments
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                // Only check lines with func declarations
                guard trimmed.contains("func ") else { continue }

                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if pattern.firstMatch(in: trimmed, range: range) != nil {
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S1172: Found \(violations.count) `_paramName` patterns (use bare `_` instead):\n\(report)")
        }
    }

    // MARK: - S1659: Multiple Variables Per Declaration

    /// Verifies no multiple variable declarations on a single line.
    func testS1659_OneVariablePerDeclaration() throws {
        let files = swiftFiles(in: sourceRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        // Pattern: `var/let x = ..., y = ...` — comma-separated variable declarations
        let pattern = try NSRegularExpression(
            pattern: #"(?:var|let)\s+\w+\s*(?::\s*\w+)?\s*=\s*[^,]+,\s*\w+\s*(?::\s*\w+)?\s*="#
        )

        for fileURL in files {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip comments
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                // Skip control flow statements (if let, guard let, while let, for)
                // These use commas for multiple conditions, not multiple declarations
                if trimmed.hasPrefix("if ") || trimmed.hasPrefix("guard ") ||
                   trimmed.hasPrefix("while ") || trimmed.hasPrefix("for ") ||
                   trimmed.hasPrefix("} else if ") { continue }

                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if pattern.firstMatch(in: trimmed, range: range) != nil {
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S1659: Found \(violations.count) multiple variable declarations on a single line:\n\(report)")
        }
    }
}
