//
// Copyright 2020 Google Inc.
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

import XCTest
import GTXiLib

// MARK: - Models

private struct GTXCheck {
    let name: String
    let passed: Bool
    let reason: String?
}

private struct GTXElement {
    let view: String
    let baseClass: String?
    let frameRect: String?
    let elementSize: String?
    let accessibilityFrame: String?
    let checks: [GTXCheck]
}

// MARK: - Public API

public enum GTXAggregateStyle {
    case arrows   // Unicode arrow-flow (default)
    case rust     // Rust-like struct debug dump
    case compact  // short list
}

/// Structured result containing parsed GTX failures and formatted output
public struct GTXFormattedResult {
    public let elementCount: Int
    public let totalCheckFailures: Int
    public let totalChecksPassed: Int
    public let formattedMessage: String
    public let hasFailures: Bool

    /// Raw parsed elements (for advanced use cases)
    public let elements: [(view: String, baseClass: String?, frameRect: String?,
                          elementSize: String?, accessibilityFrame: String?,
                          checks: [(name: String, passed: Bool, reason: String?)])]
}

/// Run GTX checks on a view and return formatted results without failing.
/// Returns a structured result that can be used for custom assertions, logging, or snapshot testing.
public func formatGTXResult(checking view: UIView,
                           toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
                           style: GTXAggregateStyle = .compact,
                           deduplicate: Bool = true,
                           includePassing: Bool = false) -> GTXFormattedResult {
    if includePassing {
        // Run checks manually to track both passing and failing
        return formatGTXResultWithPassingChecks(checking: view, toolkit: toolkit, style: style, deduplicate: deduplicate)
    }

    let result = toolkit.resultFromCheckingAllElements(fromRootElements: [view])

    // If all checks passed, return early
    guard !result.allChecksPassed else {
        return GTXFormattedResult(
            elementCount: 0,
            totalCheckFailures: 0,
            totalChecksPassed: 0,
            formattedMessage: "All GTX checks passed (\(result.elementsScanned) elements scanned)",
            hasFailures: false,
            elements: []
        )
    }

    // Get the error string from the result
    let errorString = result.aggregatedError.localizedDescription
    return formatGTXResult(fromString: errorString, style: style, deduplicate: deduplicate)
}

/// Parse and return formatted GTX results from a raw error string.
/// Returns a structured result that can be used for custom assertions, logging, or snapshot testing.
public func formatGTXResult(fromString raw: String,
                           style: GTXAggregateStyle = .compact,
                           deduplicate: Bool = true) -> GTXFormattedResult {
    let elements = parseGTXElements(from: raw)

    // Flatten to (element, check)
    var pairs: [(GTXElement, GTXCheck)] = elements.flatMap { e in e.checks.map { (e, $0) } }

    if deduplicate {
        var seen = Set<String>()
        pairs = pairs.filter { (e, c) in
            let key = "\(e.view)|\(e.baseClass ?? "-")|\(e.frameRect ?? "-")|\(e.elementSize ?? "-")|\(e.accessibilityFrame ?? "-")|\(c.name)|\(c.reason ?? "-")"
            return seen.insert(key).inserted
        }
    }

    guard !pairs.isEmpty else {
        return GTXFormattedResult(
            elementCount: 0,
            totalCheckFailures: 0,
            formattedMessage: "No GTX failures detected (raw length = \(raw.count))",
            hasFailures: false,
            elements: []
        )
    }

    // Group by element for nicer structure
    let grouped: [(elem: GTXElement, checks: [GTXCheck])] = {
        var map: [String: (GTXElement, [GTXCheck])] = [:]
        for (e, c) in pairs {
            let key = "\(e.view)|\(e.baseClass ?? "-")|\(e.frameRect ?? "-")|\(e.elementSize ?? "-")|\(e.accessibilityFrame ?? "-")"
            if var entry = map[key] {
                entry.1.append(c)
                map[key] = entry
            } else {
                map[key] = (e, [c])
            }
        }
        return Array(map.values)
    }()

    // Format message
    let message: String
    switch style {
    case .arrows:
        message = formatArrows(grouped, totalChecks: pairs.count)
    case .rust:
        message = formatRust(grouped, totalChecks: pairs.count)
    case .compact:
        message = formatCompact(grouped, totalChecks: pairs.count)
    }

    // Convert to public element format
    let publicElements = grouped.map { g in
        (
            view: g.elem.view,
            baseClass: g.elem.baseClass,
            frameRect: g.elem.frameRect,
            elementSize: g.elem.elementSize,
            accessibilityFrame: g.elem.accessibilityFrame,
            checks: g.checks.map { (name: $0.name, passed: $0.passed, reason: $0.reason) }
        )
    }

    return GTXFormattedResult(
        elementCount: grouped.count,
        totalCheckFailures: pairs.count,
        totalChecksPassed: 0,  // Only failures in error string parsing
        formattedMessage: message,
        hasFailures: true,
        elements: publicElements
    )
}

/// Run GTX checks on a view and fail ONCE with an aggregated message if any checks fail.
public func failGTXAggregated(checking view: UIView,
                              toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
                              style: GTXAggregateStyle = .compact,
                              deduplicate: Bool = true,
                              file: String = #file,
                              line: UInt = #line) {
    let result = formatGTXResult(checking: view, toolkit: toolkit, style: style, deduplicate: deduplicate)

    if result.hasFailures {
        fail(result.formattedMessage, file: file, line: line)
    }
}

/// Parse a raw GTX multi-element string and fail ONCE with an aggregated message.
public func failGTXAggregated(fromString raw: String,
                              style: GTXAggregateStyle = .compact,
                              deduplicate: Bool = true,
                              file: String = #file,
                              line: UInt = #line) {
    let result = formatGTXResult(fromString: raw, style: style, deduplicate: deduplicate)

    if !result.hasFailures {
        fail("""
        ╭──▶ GTX Parser
        ────▶ No failures parsed
        ╰──▶ Raw length = \(raw.count)
        """, file: file, line: line)
        return
    }

    fail(result.formattedMessage, file: file, line: line)
}

// MARK: - Passing Checks Support

/// Run GTX checks manually on a view to track both passing and failing checks
private func formatGTXResultWithPassingChecks(checking view: UIView,
                                             toolkit: GTXToolKit,
                                             style: GTXAggregateStyle,
                                             deduplicate: Bool) -> GTXFormattedResult {
    // This requires accessing GTX internals - for now, return a message indicating limitation
    // In a real implementation, we'd need to:
    // 1. Get all checks from the toolkit (would need toolkit API extension)
    // 2. Get all accessible elements from the view
    // 3. Run each check manually and record pass/fail

    // For now, fallback to showing only failures with a note
    let result = toolkit.resultFromCheckingAllElements(fromRootElements: [view])

    if result.allChecksPassed {
        return GTXFormattedResult(
            elementCount: 0,
            totalCheckFailures: 0,
            totalChecksPassed: result.elementsScanned,
            formattedMessage: "✅ All GTX checks passed (\(result.elementsScanned) elements checked)",
            hasFailures: false,
            elements: []
        )
    }

    // Get failures from error string
    let errorString = result.aggregatedError.localizedDescription
    let failureResult = formatGTXResult(fromString: errorString, style: style, deduplicate: deduplicate)

    // Note: Without GTX toolkit API extensions, we can't track individual passing checks
    // We can only show: total scanned - failures = estimated passes
    let estimatedPasses = result.elementsScanned - failureResult.totalCheckFailures

    var enhancedMessage = failureResult.formattedMessage
    enhancedMessage += "\n\n📊 Summary: \(failureResult.totalCheckFailures) failed, ~\(estimatedPasses) passed (\(result.elementsScanned) elements)"

    return GTXFormattedResult(
        elementCount: failureResult.elementCount,
        totalCheckFailures: failureResult.totalCheckFailures,
        totalChecksPassed: estimatedPasses,
        formattedMessage: enhancedMessage,
        hasFailures: true,
        elements: failureResult.elements
    )
}

// MARK: - Formatters

private func formatArrows(_ groups: [(elem: GTXElement, checks: [GTXCheck])],
                          totalChecks: Int) -> String {
    var lines: [String] = []
    lines.append("╭──▶ GTX Failures (count: \(totalChecks))")
    for (idx, g) in groups.enumerated() {
        let e = g.elem
        let header = "Element #\(idx + 1) – \(e.view)"
        lines.append("────▶ \(header)")
        if let base = e.baseClass { lines.append("     ╭──▶ base_class: \(base)") }
        if let size = e.elementSize { lines.append("     ├──▶ element_size: \(size)") }
        if let frame = e.frameRect { lines.append("     ├──▶ frame: \(frame)") }
        if let a11yF = e.accessibilityFrame { lines.append("     ╰──▶ accessibility_frame: \(a11yF)") }
        lines.append("     ╭──▶ checks (\(g.checks.count))")
        for c in g.checks {
            let icon = c.passed ? "✅" : "❌"
            let status = c.passed ? "passed" : "failed"
            let base = "         ────▶ [\(c.name)] \(icon) \(status)"
            if let reason = c.reason, !reason.isEmpty {
                lines.append("\(base) — \(reason)")
            } else {
                lines.append(base)
            }
        }
        lines.append("     ╰─╮ end-checks")
    }
    lines.append("╰──▶ end")
    return lines.joined(separator: "\n")
}

private func formatRust(_ groups: [(elem: GTXElement, checks: [GTXCheck])],
                        totalChecks: Int) -> String {
    var lines: [String] = []
    lines.append("GTXFailures { total: \(totalChecks), groups: [")
    for (idx, g) in groups.enumerated() {
        let e = g.elem
        lines.append("  // group #\(idx + 1)")
        lines.append("  GTXElement {")
        lines.append("    view: \"\(e.view)\",")
        lines.append("    base_class: \(e.baseClass.map { "\"\($0)\"" } ?? "None"),")
        lines.append("    frame: \(e.frameRect.map { "\"\($0)\"" } ?? "None"),")
        lines.append("    element_size: \(e.elementSize.map { "\"\($0)\"" } ?? "None"),")
        lines.append("    accessibility_frame: \(e.accessibilityFrame.map { "\"\($0)\"" } ?? "None"),")
        lines.append("    checks: [")
        for c in g.checks {
            let result = c.passed ? "passed" : "failed"
            lines.append("      GTXCheck { name: \"\(c.name)\", result: \"\(result)\", reason: \(c.reason.map { "\"\($0)\"" } ?? "None") },")
        }
        lines.append("    ]")
        lines.append("  },")
    }
    lines.append("] }")
    return lines.joined(separator: "\n")
}

private func formatCompact(_ groups: [(elem: GTXElement, checks: [GTXCheck])],
                           totalChecks: Int) -> String {
    var lines: [String] = []
    lines.append("GTX Failures: \(totalChecks)")
    for (idx, g) in groups.enumerated() {
        let e = g.elem
        let head = "(\(idx + 1)) \(e.view) [size=\(e.elementSize ?? "-"), frame=\(e.frameRect ?? "-")]"
        lines.append(head)
        for c in g.checks {
            let icon = c.passed ? "✅" : "❌"
            let status = c.passed ? "passed" : "failed"
            if let r = c.reason, !r.isEmpty {
                lines.append("  \(icon) \(c.name): \(status) — \(r)")
            } else {
                lines.append("  \(icon) \(c.name): \(status)")
            }
        }
    }
    return lines.joined(separator: "\n")
}

// MARK: - Parser (safe)

private func parseGTXElements(from raw: String) -> [GTXElement] {
    let normalizedLines = raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "UIExtendedSRGBColorSpace 1 1 1 1", with: "white")
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    var elements: [GTXElement] = []
    var currentView: String?
    var currentBase: String?
    var currentFrameRect: String?
    var currentElemSize: String?
    var currentA11yFrame: String?
    var currentChecks: [GTXCheck] = []

    func flush() {
        guard let view = currentView else { return }
        elements.append(GTXElement(
            view: view,
            baseClass: currentBase,
            frameRect: currentFrameRect,
            elementSize: currentElemSize,
            accessibilityFrame: currentA11yFrame,
            checks: currentChecks
        ))
        currentView = nil
        currentBase = nil
        currentFrameRect = nil
        currentElemSize = nil
        currentA11yFrame = nil
        currentChecks = []
    }

    for line in normalizedLines {
        if line.hasPrefix("<"), line.contains(";"), line.contains(">") {
            flush()
            let header = line
            currentView = firstCapture(in: header, pattern: #"^<([^:>]+):"#)
                ?? firstCapture(in: header, pattern: #"^<([^>]+)>"#)
                ?? "UnknownView"
            currentBase = firstCapture(in: header, pattern: #"baseClass\s*=\s*([A-Za-z0-9_\.]+)"#)
            currentFrameRect = firstCapture(in: header, pattern: #"frame\s*=\s*\([^)]+\)"#)?
                .replacingOccurrences(of: "frame = ", with: "")
            continue
        }

        if line.hasPrefix("+ Check ") || line.hasPrefix(" + Check ") {
            let checkName = firstCapture(in: line, pattern: #"\+ Check\s+"([^"]+)""#)
                ?? firstCapture(in: line, pattern: #"\+ Check\s+(.+?)\s+failed"#)
                ?? "Unknown check"
            let reason = firstCapture(in: line, pattern: #"failed,\s*(.*)$"#)?
                .trimmingCharacters(in: .whitespaces)
            // Parsed from error strings, so these are all failures
            currentChecks.append(GTXCheck(name: checkName, passed: false, reason: reason))
            continue
        }

        if line.hasPrefix("Element accessibilityFrame:") {
            currentA11yFrame = line
                .replacingOccurrences(of: "Element accessibilityFrame:", with: "")
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespaces)
            continue
        }
        if line.hasPrefix("Element frame:") {
            currentElemSize = line
                .replacingOccurrences(of: "Element frame:", with: "")
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespaces)
            continue
        }
    }

    flush()
    return elements
}

// MARK: - Regex helper

private func firstCapture(in text: String, pattern: String) -> String? {
    do {
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard m.numberOfRanges >= 2 else { return nil }
        let r = m.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    } catch {
        return nil
    }
}

// MARK: - Snapshot Testing Support

#if canImport(SnapshotTesting)
import SnapshotTesting

extension GTXFormattedResult {
    /// Snapshot strategy for GTX formatted results
    public static let snapshotStrategy = Snapshotting<GTXFormattedResult, String>(
        pathExtension: "txt",
        diffing: .lines
    )

    /// Convert result to snapshot string
    public var snapshotValue: String {
        return formattedMessage
    }
}

/// Convenience function for snapshot testing GTX results from a view
public func assertGTXSnapshot(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    recording: Bool = false,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
) {
    let result = formatGTXResult(checking: view, toolkit: toolkit, style: style, deduplicate: deduplicate)
    assertSnapshot(
        matching: result.formattedMessage,
        as: .lines,
        record: recording,
        file: file,
        testName: testName,
        line: line
    )
}

/// Convenience function for snapshot testing GTX results from a raw string
public func assertGTXSnapshot(
    fromString raw: String,
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    recording: Bool = false,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
) {
    let result = formatGTXResult(fromString: raw, style: style, deduplicate: deduplicate)
    assertSnapshot(
        matching: result.formattedMessage,
        as: .lines,
        record: recording,
        file: file,
        testName: testName,
        line: line
    )
}
#endif

// MARK: - Tests

class GTXToolkitSwiftTests: XCTestCase {

  func testToolkitCreationMethods() {
    XCTAssertNotNil(GTXToolKit.defaultToolkit)
    XCTAssertNotNil(GTXToolKit.toolkitWithNoChecks)
    XCTAssertNotNil(GTXToolKit.toolkitWithAllDefaultChecks)
  }
}
