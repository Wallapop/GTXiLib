//
// Copyright 2025 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import UIKit

// MARK: - Models

/// Summary statistics for a single test case
public struct TestCaseSummary {
    public let status: String  // "PASSED" or "FAILED"
    public let elementsScanned: Int
    public let elementsWithFailures: Int
    public let totalCheckFailures: Int
}

/// Represents a single failing element with all its check failures
public struct FailingElement {
    public let id: Int
    public let view: String
    public let text: String?
    public let baseClass: String?
    public let frameRect: String?
    public let elementSize: String?
    public let accessibilityFrame: String?
    public let checks: [(name: String, reason: String?)]
}

/// Result for a single test case
public struct TestCaseResult {
    public let summary: TestCaseSummary
    public let screenshot: String?
    public let failingElements: [FailingElement]
}

/// Global summary across all test cases
public struct GlobalSummary {
    public let totalTestCases: Int
    public let passedTestCases: Int
    public let failedTestCases: Int
    public let totalElementsScanned: Int
    public let totalFailingElements: Int
    public let totalCheckFailures: Int
}

// MARK: - YAML Parse Error

public enum YAMLParseError: Error, CustomStringConvertible {
    case fileNotFound(path: String)
    case malformedStructure(line: Int, reason: String)
    case missingRequiredField(field: String, context: String)
    case invalidValue(field: String, value: String, expected: String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "YAML file not found at path: \(path)"
        case .malformedStructure(let line, let reason):
            return "Malformed YAML structure at line \(line): \(reason)"
        case .missingRequiredField(let field, let context):
            return "Missing required field '\(field)' in \(context)"
        case .invalidValue(let field, let value, let expected):
            return "Invalid value '\(value)' for field '\(field)', expected \(expected)"
        }
    }
}

// MARK: - GTXAggregator

/// Manages aggregation of multiple GTX accessibility test results into a single YAML report.
/// Thread-safe for concurrent test execution.
public class GTXAggregator {
    private let outputPath: String
    private var testCases: [String: TestCaseResult] = [:]
    private let lock = NSLock()

    /// Initialize aggregator with path to aggregated YAML file
    /// - Parameter aggregatedYAMLPath: Path where the aggregated YAML will be saved
    public init(aggregatedYAMLPath: String) {
        self.outputPath = aggregatedYAMLPath

        // Load existing results if file exists
        if FileManager.default.fileExists(atPath: aggregatedYAMLPath) {
            do {
                try loadExistingReport()
            } catch {
                print("⚠️ Failed to load existing aggregated YAML: \(error)")
                print("   Starting with empty test case collection")
            }
        }
    }

    /// Check if a test case already exists in the aggregated report
    /// - Parameter testName: Name of the test case
    /// - Returns: true if test case exists, false otherwise
    public func testCaseExists(_ testName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return testCases[testName] != nil
    }

    /// Get the current YAML content as a string
    /// - Returns: The YAML content that would be written to disk
    public func getCurrentYAMLContent() -> String {
        lock.lock()
        defer { lock.unlock() }

        var yaml = "# GTX Accessibility Report - Aggregated Results\n\n"

        // Global summary
        let summary = _globalSummaryUnsafe()
        yaml += "globalSummary:\n"
        yaml += "  totalTestCases: \(summary.totalTestCases)\n"
        yaml += "  passedTestCases: \(summary.passedTestCases)\n"
        yaml += "  failedTestCases: \(summary.failedTestCases)\n"
        yaml += "  totalElementsScanned: \(summary.totalElementsScanned)\n"
        yaml += "  totalFailingElements: \(summary.totalFailingElements)\n"
        yaml += "  totalCheckFailures: \(summary.totalCheckFailures)\n\n"

        // Test cases (sorted by name for stability)
        yaml += "testCases:\n"
        for (testName, result) in testCases.sorted(by: { $0.key < $1.key }) {
            yaml += "  \"\(testName)\":\n"

            // Summary
            yaml += "    summary:\n"
            yaml += "      status: \"\(result.summary.status)\"\n"
            yaml += "      elementsScanned: \(result.summary.elementsScanned)\n"
            yaml += "      elementsWithFailures: \(result.summary.elementsWithFailures)\n"
            yaml += "      totalCheckFailures: \(result.summary.totalCheckFailures)\n"

            // Screenshot
            if let screenshot = result.screenshot {
                yaml += "    screenshot: \"\(screenshot)\"\n"
            }

            // Failing elements
            if result.summary.status == "FAILED" {
                if !result.failingElements.isEmpty {
                    yaml += "    failingElements:\n"
                    for element in result.failingElements {
                        yaml += "      - id: \(element.id)\n"
                        yaml += "        view: \(yamlString(element.view))\n"
                        if let text = element.text, !text.isEmpty {
                            yaml += "        text: \(yamlString(text))\n"
                        }
                        if let baseClass = element.baseClass, !baseClass.isEmpty {
                            yaml += "        baseClass: \(yamlString(baseClass))\n"
                        }
                        if let frameRect = element.frameRect, !frameRect.isEmpty {
                            yaml += "        frameRect: \(yamlString(frameRect))\n"
                        }
                        if let elementSize = element.elementSize, !elementSize.isEmpty {
                            yaml += "        elementSize: \(yamlString(elementSize))\n"
                        }
                        if let a11yFrame = element.accessibilityFrame, !a11yFrame.isEmpty {
                            yaml += "        accessibilityFrame: \(yamlString(a11yFrame))\n"
                        }
                        yaml += "        checks:\n"
                        for check in element.checks {
                            yaml += "          - name: \(yamlString(check.name))\n"
                            yaml += "            reason: \(yamlString(check.reason ?? ""))\n"
                        }
                    }
                } else {
                    yaml += "    failingElements: []  # Test failed but no specific elements were recorded\n"
                }
            }
            yaml += "\n"
        }

        return yaml
    }

    /// Compare a specific test case with what's saved on disk
    /// - Parameter testName: Name of the test case to compare
    /// - Returns: tuple (matches: Bool, diff: String?) - diff is populated if content differs
    public func compareTestCase(_ testName: String) -> (matches: Bool, diff: String?) {
        // First check if we have the test case in memory
        guard let currentTestCase = testCases[testName] else {
            return (false, "Test case not found in current results")
        }

        // Try to load the saved file and parse it
        guard FileManager.default.fileExists(atPath: outputPath) else {
            return (false, "YAML file does not exist on disk - this is a new test")
        }

        guard let savedContent = try? String(contentsOfFile: outputPath, encoding: .utf8) else {
            return (false, "Failed to read saved YAML file")
        }

        // Parse the saved YAML to extract the specific test case
        let savedTestCases: [String: TestCaseResult]
        do {
            savedTestCases = try parseAggregatedYAML(savedContent)
        } catch {
            return (false, "Failed to parse saved YAML: \(error)")
        }

        // Check if this specific test case exists in the saved file
        guard let savedTestCase = savedTestCases[testName] else {
            return (false, "Test case '\(testName)' not found in saved YAML - this is a new test")
        }

        let currentYAML = formatTestCaseAsYAML(testName: testName, result: currentTestCase)
        let savedYAML = formatTestCaseAsYAML(testName: testName, result: savedTestCase)

        if currentYAML == savedYAML {
            return (true, nil)
        }

        let diff = generateDiff(saved: savedYAML, current: currentYAML)
        return (false, diff)
    }

    /// Format a single test case as YAML (for comparison)
    private func formatTestCaseAsYAML(testName: String, result: TestCaseResult) -> String {
        var yaml = "\"\(testName)\":\n"

        // Summary
        yaml += "  summary:\n"
        yaml += "    status: \"\(result.summary.status)\"\n"
        yaml += "    elementsScanned: \(result.summary.elementsScanned)\n"
        yaml += "    elementsWithFailures: \(result.summary.elementsWithFailures)\n"
        yaml += "    totalCheckFailures: \(result.summary.totalCheckFailures)\n"

        // Screenshot
        if let screenshot = result.screenshot {
            yaml += "  screenshot: \"\(screenshot)\"\n"
        }

        // Failing elements
        if result.summary.status == "FAILED" {
            if !result.failingElements.isEmpty {
                yaml += "  failingElements:\n"
                for element in result.failingElements {
                    yaml += "    - id: \(element.id)\n"
                    yaml += "      view: \(yamlString(element.view))\n"
                    if let text = element.text, !text.isEmpty {
                        yaml += "      text: \(yamlString(text))\n"
                    }
                    if let baseClass = element.baseClass, !baseClass.isEmpty {
                        yaml += "      baseClass: \(yamlString(baseClass))\n"
                    }
                    if let frameRect = element.frameRect, !frameRect.isEmpty {
                        yaml += "      frameRect: \(yamlString(frameRect))\n"
                    }
                    if let elementSize = element.elementSize, !elementSize.isEmpty {
                        yaml += "      elementSize: \(yamlString(elementSize))\n"
                    }
                    if let a11yFrame = element.accessibilityFrame, !a11yFrame.isEmpty {
                        yaml += "      accessibilityFrame: \(yamlString(a11yFrame))\n"
                    }
                    yaml += "      checks:\n"
                    for check in element.checks {
                        yaml += "        - name: \(yamlString(check.name))\n"
                        yaml += "          reason: \(yamlString(check.reason ?? ""))\n"
                    }
                }
            } else {
                yaml += "  failingElements: []  # Test failed but no specific elements were recorded\n"
            }
        }

        return yaml
    }

    /// Generate a readable diff between two strings
    private func generateDiff(saved: String, current: String) -> String {
        let savedLines = saved.components(separatedBy: .newlines)
        let currentLines = current.components(separatedBy: .newlines)

        var diff = "\n" + String(repeating: "=", count: 80) + "\n"
        diff += "YAML CONTENT DIFF\n"
        diff += String(repeating: "=", count: 80) + "\n\n"

        // Simple line-by-line comparison
        let maxLines = max(savedLines.count, currentLines.count)
        var differenceCount = 0

        for i in 0..<maxLines {
            let savedLine = i < savedLines.count ? savedLines[i] : "<missing>"
            let currentLine = i < currentLines.count ? currentLines[i] : "<missing>"

            if savedLine != currentLine {
                differenceCount += 1
                if differenceCount <= 20 { // Show first 20 differences
                    diff += "Line \(i + 1):\n"
                    diff += "  - SAVED:   \(savedLine)\n"
                    diff += "  + CURRENT: \(currentLine)\n\n"
                }
            }
        }

        if differenceCount > 20 {
            diff += "... and \(differenceCount - 20) more differences\n\n"
        }

        diff += String(repeating: "=", count: 80) + "\n"
        diff += "Total differences: \(differenceCount) lines\n"
        diff += String(repeating: "=", count: 80) + "\n"

        return diff
    }

    /// Add or update a test result in the aggregated report
    /// - Parameters:
    ///   - testName: Name of the test case
    ///   - result: Formatted GTX result containing violations
    ///   - screenshotName: Name of the screenshot file (not full path)
    public func addTestResult(_ testName: String,
                              result: GTXFormattedResult,
                              screenshotName: String?) {
        lock.lock()
        defer { lock.unlock() }

        // Build summary
        let summary = TestCaseSummary(
            status: result.hasFailures ? "FAILED" : "PASSED",
            elementsScanned: result.elementCount + result.totalChecksPassed,
            elementsWithFailures: result.elementCount,
            totalCheckFailures: result.totalCheckFailures
        )

        // Convert GTXElementResult to FailingElement format
        let failingElements: [FailingElement] = result.elements.map { element in
            FailingElement(
                id: element.id,
                view: element.view,
                text: element.text,
                baseClass: element.baseClass,
                frameRect: element.frameRect,
                elementSize: element.elementSize,
                accessibilityFrame: element.accessibilityFrame,
                checks: element.checks.map { (name: $0.name, reason: $0.reason) }
            )
        }

        testCases[testName] = TestCaseResult(
            summary: summary,
            screenshot: screenshotName,
            failingElements: failingElements
        )
    }

    /// Calculate global summary statistics across all test cases
    /// - Returns: Global summary with aggregate counts
    public func globalSummary() -> GlobalSummary {
        lock.lock()
        defer { lock.unlock() }

        var passedCount = 0
        var failedCount = 0
        var totalElementsScanned = 0
        var totalFailingElements = 0
        var totalCheckFailures = 0

        for (_, result) in testCases {
            if result.summary.status == "PASSED" {
                passedCount += 1
            } else {
                failedCount += 1
            }
            totalElementsScanned += result.summary.elementsScanned
            totalFailingElements += result.summary.elementsWithFailures
            totalCheckFailures += result.summary.totalCheckFailures
        }

        return GlobalSummary(
            totalTestCases: testCases.count,
            passedTestCases: passedCount,
            failedTestCases: failedCount,
            totalElementsScanned: totalElementsScanned,
            totalFailingElements: totalFailingElements,
            totalCheckFailures: totalCheckFailures
        )
    }

    /// Save the aggregated report to disk as YAML
    /// Writes directly to the output path with atomic flag (no temp files)
    /// - Throws: Error if write fails
    public func save() throws {
        lock.lock()
        defer { lock.unlock() }

        var yaml = "# GTX Accessibility Report - Aggregated Results\n\n"

        // Global summary
        let summary = _globalSummaryUnsafe()
        yaml += "globalSummary:\n"
        yaml += "  totalTestCases: \(summary.totalTestCases)\n"
        yaml += "  passedTestCases: \(summary.passedTestCases)\n"
        yaml += "  failedTestCases: \(summary.failedTestCases)\n"
        yaml += "  totalElementsScanned: \(summary.totalElementsScanned)\n"
        yaml += "  totalFailingElements: \(summary.totalFailingElements)\n"
        yaml += "  totalCheckFailures: \(summary.totalCheckFailures)\n\n"

        // Test cases (sorted by name for stability)
        yaml += "testCases:\n"
        for (testName, result) in testCases.sorted(by: { $0.key < $1.key }) {
            yaml += "  \"\(testName)\":\n"

            // Summary
            yaml += "    summary:\n"
            yaml += "      status: \"\(result.summary.status)\"\n"
            yaml += "      elementsScanned: \(result.summary.elementsScanned)\n"
            yaml += "      elementsWithFailures: \(result.summary.elementsWithFailures)\n"
            yaml += "      totalCheckFailures: \(result.summary.totalCheckFailures)\n"

            // Screenshot
            if let screenshot = result.screenshot {
                yaml += "    screenshot: \"\(screenshot)\"\n"
            }

            // Failing elements
            if result.summary.status == "FAILED" {
                if !result.failingElements.isEmpty {
                    yaml += "    failingElements:\n"
                    for element in result.failingElements {
                        yaml += "      - id: \(element.id)\n"
                        yaml += "        view: \(yamlString(element.view))\n"
                        if let text = element.text, !text.isEmpty {
                            yaml += "        text: \(yamlString(text))\n"
                        }
                        if let baseClass = element.baseClass, !baseClass.isEmpty {
                            yaml += "        baseClass: \(yamlString(baseClass))\n"
                        }
                        if let frameRect = element.frameRect, !frameRect.isEmpty {
                            yaml += "        frameRect: \(yamlString(frameRect))\n"
                        }
                        if let elementSize = element.elementSize, !elementSize.isEmpty {
                            yaml += "        elementSize: \(yamlString(elementSize))\n"
                        }
                        if let a11yFrame = element.accessibilityFrame, !a11yFrame.isEmpty {
                            yaml += "        accessibilityFrame: \(yamlString(a11yFrame))\n"
                        }
                        yaml += "        checks:\n"
                        for check in element.checks {
                            yaml += "          - name: \(yamlString(check.name))\n"
                            yaml += "            reason: \(yamlString(check.reason ?? ""))\n"
                        }
                    }
                } else {
                    yaml += "    failingElements: []  # Test failed but no specific elements were recorded\n"
                }
            }
            yaml += "\n"
        }

        // Ensure parent directory exists
        let parentDir = (outputPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parentDir) {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        // Write atomically (no temp file needed - String.write handles this)
        try yaml.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("📝 GTX aggregated report saved to: \(outputPath)")
    }

    // MARK: - Private Helpers

    /// Unsafe version of globalSummary() that doesn't acquire lock (caller must hold lock)
    private func _globalSummaryUnsafe() -> GlobalSummary {
        var passedCount = 0
        var failedCount = 0
        var totalElementsScanned = 0
        var totalFailingElements = 0
        var totalCheckFailures = 0

        for (_, result) in testCases {
            if result.summary.status == "PASSED" {
                passedCount += 1
            } else {
                failedCount += 1
            }
            totalElementsScanned += result.summary.elementsScanned
            totalFailingElements += result.summary.elementsWithFailures
            totalCheckFailures += result.summary.totalCheckFailures
        }

        return GlobalSummary(
            totalTestCases: testCases.count,
            passedTestCases: passedCount,
            failedTestCases: failedCount,
            totalElementsScanned: totalElementsScanned,
            totalFailingElements: totalFailingElements,
            totalCheckFailures: totalCheckFailures
        )
    }

    /// Load existing aggregated YAML file
    /// - Throws: YAMLParseError if file cannot be parsed
    private func loadExistingReport() throws {
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw YAMLParseError.fileNotFound(path: outputPath)
        }

        guard let yamlContent = try? String(contentsOfFile: outputPath, encoding: .utf8) else {
            throw YAMLParseError.fileNotFound(path: outputPath)
        }

        testCases = try parseAggregatedYAML(yamlContent)
    }

    /// Parse aggregated YAML content into test case results
    /// - Parameter content: YAML content as string
    /// - Returns: Dictionary of test name to test case result
    /// - Throws: YAMLParseError if content is malformed
    private func parseAggregatedYAML(_ content: String) throws -> [String: TestCaseResult] {
        var results: [String: TestCaseResult] = [:]

        let lines = content.components(separatedBy: .newlines)
        var currentTestCase: String?
        var currentSummary: TestCaseSummary?
        var currentScreenshot: String?
        var failingElements: [FailingElement] = []
        var currentElement: (id: Int, view: String, text: String?, baseClass: String?, frameRect: String?, elementSize: String?, a11yFrame: String?)?
        var currentChecks: [(name: String, reason: String?)] = []
        var inTestCases = false
        var inSummary = false
        var inFailingElements = false
        var inElement = false
        var inChecks = false

        // Summary field accumulators
        var summaryStatus: String?
        var summaryElementsScanned: Int?
        var summaryElementsWithFailures: Int?
        var summaryTotalCheckFailures: Int?

        func flush() {
            guard let testName = currentTestCase, let summary = currentSummary else { return }

            // Save current element if any
            if let elem = currentElement {
                let element = FailingElement(
                    id: elem.id,
                    view: elem.view,
                    text: elem.text,
                    baseClass: elem.baseClass,
                    frameRect: elem.frameRect,
                    elementSize: elem.elementSize,
                    accessibilityFrame: elem.a11yFrame,
                    checks: currentChecks
                )
                failingElements.append(element)
            }

            results[testName] = TestCaseResult(
                summary: summary,
                screenshot: currentScreenshot,
                failingElements: failingElements
            )

            // Reset state
            currentTestCase = nil
            currentSummary = nil
            currentScreenshot = nil
            failingElements = []
            currentElement = nil
            currentChecks = []
            inSummary = false
            inFailingElements = false
            inElement = false
            inChecks = false
            // Reset summary accumulators
            summaryStatus = nil
            summaryElementsScanned = nil
            summaryElementsWithFailures = nil
            summaryTotalCheckFailures = nil
        }

        for (lineNum, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }

            // Detect testCases section
            if trimmed == "testCases:" {
                inTestCases = true
                continue
            }

            // Detect test case name
            if inTestCases && line.hasPrefix("  \"") && trimmed.hasSuffix(":") {
                flush()  // Save previous test case
                let testName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                currentTestCase = testName
                continue
            }

            // Detect summary section
            if trimmed.hasPrefix("summary:") {
                inSummary = true
                inFailingElements = false
                // Reset summary field accumulators
                summaryStatus = nil
                summaryElementsScanned = nil
                summaryElementsWithFailures = nil
                summaryTotalCheckFailures = nil
                continue
            }

            // Parse summary fields as we encounter them
            if inSummary, let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                let value = unescapeYAMLString(rawValue)

                switch key {
                case "status":
                    summaryStatus = value
                case "elementsScanned":
                    summaryElementsScanned = Int(value)
                case "elementsWithFailures":
                    summaryElementsWithFailures = Int(value)
                case "totalCheckFailures":
                    summaryTotalCheckFailures = Int(value)
                    // After totalCheckFailures, construct the summary
                    currentSummary = TestCaseSummary(
                        status: summaryStatus ?? "UNKNOWN",
                        elementsScanned: summaryElementsScanned ?? 0,
                        elementsWithFailures: summaryElementsWithFailures ?? 0,
                        totalCheckFailures: summaryTotalCheckFailures ?? 0
                    )
                    inSummary = false
                default:
                    break
                }
                continue
            }

            // Screenshot field
            if trimmed.hasPrefix("screenshot:") {
                if let colonIndex = trimmed.firstIndex(of: ":") {
                    let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    currentScreenshot = unescapeYAMLString(rawValue)
                }
                continue
            }

            // Failing elements section
            if trimmed.hasPrefix("failingElements:") {
                inFailingElements = true
                inElement = false
                inChecks = false
                continue
            }

            // Parse failing element
            if inFailingElements && trimmed.hasPrefix("- id:") {
                // Save previous element
                if let elem = currentElement {
                    let element = FailingElement(
                        id: elem.id,
                        view: elem.view,
                        text: elem.text,
                        baseClass: elem.baseClass,
                        frameRect: elem.frameRect,
                        elementSize: elem.elementSize,
                        accessibilityFrame: elem.a11yFrame,
                        checks: currentChecks
                    )
                    failingElements.append(element)
                }

                // Start new element
                if let idValue = trimmed.split(separator: ":").last?.trimmingCharacters(in: .whitespaces), let id = Int(idValue) {
                    currentElement = (id: id, view: "", text: nil, baseClass: nil, frameRect: nil, elementSize: nil, a11yFrame: nil)
                    currentChecks = []
                    inElement = true
                    inChecks = false
                }
                continue
            }

            // Parse element fields
            if inElement && !inChecks, let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                let value = unescapeYAMLString(rawValue)

                guard var elem = currentElement else { continue }

                switch key {
                case "view":
                    elem.view = value
                case "text":
                    elem.text = value
                case "baseClass":
                    elem.baseClass = value
                case "frameRect":
                    elem.frameRect = value
                case "elementSize":
                    elem.elementSize = value
                case "accessibilityFrame":
                    elem.a11yFrame = value
                case "checks":
                    inChecks = true
                    continue
                default:
                    break
                }

                currentElement = elem
                continue
            }

            // Parse checks
            if inChecks && trimmed.hasPrefix("- name:") {
                if let rawValue = trimmed.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) {
                    let nameValue = unescapeYAMLString(rawValue)
                    currentChecks.append((name: nameValue, reason: nil))
                }
                continue
            }

            if inChecks && trimmed.hasPrefix("reason:") {
                if var lastCheck = currentChecks.last {
                    if let rawValue = trimmed.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) {
                        let reasonValue = unescapeYAMLString(rawValue)
                        currentChecks[currentChecks.count - 1] = (name: lastCheck.name, reason: reasonValue)
                    }
                }
                continue
            }
        }

        // Flush last test case
        flush()

        return results
    }

    /// Helper to extract summary field value
    private func extractSummaryField(from lines: [String], startLine: Int, field: String, context: String) -> String? {
        // Search backwards from startLine for the field
        for i in stride(from: startLine, through: max(0, startLine - 10), by: -1) {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(field):"), let colonIndex = trimmed.firstIndex(of: ":") {
                return String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    /// Format a string value for YAML output (escaping if needed)
    private func yamlString(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }
        if value.contains("\"") || value.contains("\n") || value.contains(":") || value.contains("#") {
            var escaped = value
            escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
            return "\"\(escaped)\""
        }
        return "\"\(value)\""
    }

    /// Unescape a YAML string value (reverse of yamlString)
    private func unescapeYAMLString(_ value: String) -> String {
        var unescaped = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        unescaped = unescaped.replacingOccurrences(of: "\\r", with: "\r")
        unescaped = unescaped.replacingOccurrences(of: "\\n", with: "\n")
        unescaped = unescaped.replacingOccurrences(of: "\\\"", with: "\"")
        unescaped = unescaped.replacingOccurrences(of: "\\\\", with: "\\")
        return unescaped
    }
}

