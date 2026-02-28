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
    func testS1186NoEmptyClosureBodiesWithoutComment() throws {
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

                // SonarQube S1186 accepts both // and /* */ as valid nested comments.
                // Only flag `{ /* */ }` with empty block comments (no actual explanation).
                if (trimmed.contains("{ /* */ }") || trimmed.contains("{ /*  */ }")) {
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
    func testS3358NoNestedTernaryOperations() throws {
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
    func testS3661NoForceTriesInTests() throws {
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
    func testS100S117NoUnderscorePrefixedNames() throws {
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
    func testS1172NoUnderscorePrefixedParameters() throws {
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

    // MARK: - S1135: FIXME/TODO Comments

    /// Verifies no FIXME comments in production code or test files that are compiled.
    /// FIXME is flagged by SonarQube as requiring immediate action.
    /// Files wrapped in #if false are excluded since they don't compile.
    func testS1135NoFIXMEInCompiledCode() throws {
        let files = swiftFiles(in: sourceRoot) + swiftFiles(in: testRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        for fileURL in files {
            if fileURL.lastPathComponent == "SonarQubeRulesTests.swift" { continue }

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            // Track if we're inside a #if false block
            var ifFalseDepth = 0

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Track #if false / #endif nesting
                if trimmed == "#if false" { ifFalseDepth += 1 }
                if trimmed == "#endif" && ifFalseDepth > 0 { ifFalseDepth -= 1 }

                // Skip code inside #if false blocks (not compiled, won't reach SonarQube)
                if ifFalseDepth > 0 { continue }

                // Check for FIXME in comments
                if trimmed.contains("FIXME") && (trimmed.hasPrefix("//") || trimmed.hasPrefix("*")) {
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S1135: Found \(violations.count) FIXME comments in compiled code:\n\(report)")
        }
    }

    // MARK: - S1066: MediaOptimizerTests Merged If Guard

    /// Verifies MediaOptimizerTests uses merged if-let conditions (not nested if).
    func testS1066MediaOptimizerMergedIfCondition() throws {
        let fileURL = testRoot.appendingPathComponent("MediaOptimizerTests.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("if let track = try?") && trimmed.contains("estimatedDataRate") {
                // The condition should include the rate check on the same if-let chain
                XCTAssertTrue(
                    trimmed.contains("rate <=") || trimmed.contains("rate <"),
                    "Rate check should be merged into the if-let chain (S1066), not nested"
                )
                // Next line should NOT be another nested `if`
                if index + 1 < lines.count {
                    let nextTrimmed = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    XCTAssertFalse(
                        nextTrimmed.hasPrefix("if rate"),
                        "Rate check should NOT be a nested if (S1066 violation)"
                    )
                }
            }
        }
    }

    // MARK: - S3087: Extracted Closure Guards

    /// Verifies ShareImportManager uses extracted progress closure, not inline 3-deep nesting.
    func testS3087ShareImportManagerNoInlineProgressClosure() throws {
        let fileURL = sourceRoot
            .appendingPathComponent("Core/Sharing/ShareImportManager.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            content.contains("onProgress: downloadProgress"),
            "Download progress should use extracted closure variable, not inline"
        )
        XCTAssertFalse(
            content.contains("onProgress: { [weak self]"),
            "Download progress should NOT be an inline closure (causes S3087 nesting violation)"
        )
    }

    /// Verifies test files use extracted helper methods for task group worker patterns.
    func testS3087TestFilesUseExtractedWorkerHelpers() throws {
        for filename in ["ImportStreamingTests.swift", "ImportOptimizationTests.swift"] {
            let fileURL = testRoot.appendingPathComponent(filename)
            let content = try String(contentsOf: fileURL, encoding: .utf8)

            XCTAssertTrue(
                content.contains("static func runWorkStealingWorkers("),
                "\(filename) should have runWorkStealingWorkers helper"
            )
            XCTAssertTrue(
                content.contains("await Self.runWorkStealingWorkers("),
                "\(filename) should call extracted helper via Self.runWorkStealingWorkers"
            )
        }

        let optContent = try String(contentsOf: testRoot.appendingPathComponent("ImportOptimizationTests.swift"), encoding: .utf8)
        XCTAssertTrue(
            optContent.contains("static func runSplitWorkers("),
            "ImportOptimizationTests should have runSplitWorkers helper"
        )
    }

    // MARK: - S1186 Block Comment Validation

    /// Verifies that block comments in empty bodies actually contain text, not just whitespace.
    func testS1186BlockCommentsContainSubstantiveText() throws {
        let files = swiftFiles(in: sourceRoot) + swiftFiles(in: testRoot)
        var violations: [(file: String, line: Int, code: String)] = []

        let emptyBlockCommentPattern = try NSRegularExpression(
            pattern: #"\{\s*/\*\s*\*/\s*\}"#
        )

        for fileURL in files {
            if fileURL.lastPathComponent == "SonarQubeRulesTests.swift" { continue }

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let relativePath = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if emptyBlockCommentPattern.firstMatch(in: trimmed, range: range) != nil {
                    violations.append((relativePath, index + 1, trimmed))
                }
            }
        }

        if !violations.isEmpty {
            let report = violations.map { "  \($0.file):\($0.line): \($0.code)" }.joined(separator: "\n")
            XCTFail("S1186: Found \(violations.count) empty block comments (must contain explanatory text):\n\(report)")
        }
    }

    // MARK: - Specific File Regression Guards

    /// Verifies ShareVaultView cancel buttons have non-empty closures.
    func testShareVaultViewCancelButtonsHaveComments() throws {
        let fileURL = sourceRoot
            .appendingPathComponent("Features/Sharing/ShareVaultView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var cancelButtonsFound = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Button(\"Cancel\", role: .cancel)") {
                cancelButtonsFound += 1
                XCTAssertFalse(
                    trimmed.hasSuffix("{}") || trimmed.hasSuffix("{ }"),
                    "Cancel button must have a comment in its closure: \(trimmed)"
                )
                XCTAssertTrue(
                    trimmed.contains("/*") || trimmed.contains("//"),
                    "Cancel button closure must contain a comment: \(trimmed)"
                )
            }
        }
        XCTAssertGreaterThan(cancelButtonsFound, 0, "Should find at least one cancel button in ShareVaultView")
    }

    /// Verifies InactivityLockManager.PassthroughTouchRecognizer uses `_` for unused params.
    func testPassthroughTouchRecognizerUsesUnderscoreParams() throws {
        let fileURL = sourceRoot
            .appendingPathComponent("Core/InactivityLockManager.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Verify the override uses bare `_` instead of named params
        XCTAssertTrue(
            content.contains("override func touchesBegan(_: Set<UITouch>, with _: UIEvent?)"),
            "PassthroughTouchRecognizer should use `_` for unused params"
        )
        XCTAssertFalse(
            content.contains("override func touchesBegan(_ touches: Set<UITouch>"),
            "PassthroughTouchRecognizer should NOT use named params (they're unused)"
        )
    }

    /// Verifies ConceptExplainerView has a single `if animatePattern` block (not duplicated).
    func testConceptExplainerViewNoDuplicateAnimatePatternCondition() throws {
        let fileURL = sourceRoot
            .appendingPathComponent("Features/Onboarding/ConceptExplainerView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        // Count `if animatePattern {` occurrences in the PatternDemoGrid struct
        var inPatternDemoGrid = false
        var animatePatternIfCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("struct PatternDemoGrid") { inPatternDemoGrid = true }
            if inPatternDemoGrid && trimmed == "if animatePattern {" {
                animatePatternIfCount += 1
            }
            // Stop at end of struct (next struct/class/enum declaration or end of file)
            if inPatternDemoGrid && (trimmed.hasPrefix("struct ") || trimmed.hasPrefix("class "))
                && !trimmed.contains("PatternDemoGrid") {
                break
            }
        }

        XCTAssertEqual(
            animatePatternIfCount, 1,
            "PatternDemoGrid should have exactly one `if animatePattern` block (was consolidated from two)"
        )
    }

    /// Verifies ShareImportManager extracts download progress handler (not inline 3-deep closure).
    func testShareImportManagerDownloadProgressExtracted() throws {
        let fileURL = sourceRoot
            .appendingPathComponent("Core/Sharing/ShareImportManager.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Should have an extracted closure variable
        XCTAssertTrue(
            content.contains("let downloadProgress:") || content.contains("let downloadProgress ="),
            "ShareImportManager should have an extracted downloadProgress closure"
        )

        // Should use it as `onProgress: downloadProgress` (not inline)
        XCTAssertTrue(
            content.contains("onProgress: downloadProgress"),
            "ShareImportManager should pass extracted downloadProgress to onProgress parameter"
        )
    }

    /// Verifies mock protocol stubs in shared mock files have explanatory comments.
    func testMockProtocolStubsHaveComments() throws {
        let mockFiles = [
            testRoot.appendingPathComponent("Mocks/MockVaultStorage.swift"),
            testRoot.appendingPathComponent("Mocks/MockCloudKitSharing.swift"),
        ]

        var emptyMockStubs = 0
        var commentedMockStubs = 0

        for fileURL in mockFiles {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Match one-liner function stubs ending with `{ }` or `{}`
                if trimmed.contains("func ") && (trimmed.hasSuffix("{}") || trimmed.hasSuffix("{ }")) {
                    emptyMockStubs += 1
                }
                // Match one-liner stubs with comments like /* No-op */ or /* No-op for mock */
                if trimmed.contains("func ") && trimmed.contains("/* No-op") {
                    commentedMockStubs += 1
                }
            }
        }

        XCTAssertEqual(emptyMockStubs, 0,
            "All mock stubs should have comments, found \(emptyMockStubs) without")
        XCTAssertGreaterThan(commentedMockStubs, 0,
            "Should find mock stubs with /* No-op */ comments")
    }

    // MARK: - S1659: Multiple Variables Per Declaration

    /// Verifies no multiple variable declarations on a single line.
    func testS1659OneVariablePerDeclaration() throws {
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
