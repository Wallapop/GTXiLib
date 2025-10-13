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
import GTXiLib  // Import ObjC umbrella header for GTXToolKit, GTXResult, etc.

#if canImport(XCTest)
import XCTest
#endif

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

/// Output style for GTX accessibility check results
public enum GTXAggregateStyle {
    case arrows   // Unicode arrow-flow (default)
    case rust     // Rust-like struct debug dump
    case compact  // Short list
    case yaml     // YAML format for reports
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

/// Verify accessibility and optionally save a YAML report with numbered screenshot.
/// Returns error message if checks fail, nil if all pass.
///
/// Example usage:
/// ```swift
/// let errorMessage = verifyAccessibility(
///     checking: view,
///     toolkit: .toolkitWithAllDefaultChecks(),
///     style: .yaml,
///     record: "/path/to/report.yml",
///     saveScreenshot: true
/// )
/// if let errorMessage {
///     fail(errorMessage)
/// }
/// ```
public func verifyAccessibility(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    record snapshotPath: String? = nil,
    showPassingSummary: Bool = true,
    saveScreenshot: Bool = false
) -> String? {
    let result = toolkit.resultFromCheckingAllElements(fromRootElements: [view])

    // If all checks passed and we have a snapshot path, save a "passing" YAML
    if result.allChecksPassed() {
        if let snapshotPath = snapshotPath {
            let passingResult = GTXFormattedResultWithText(
                elementCount: 0,
                totalCheckFailures: 0,
                formattedMessage: "All GTX checks passed",
                hasFailures: false,
                elementsScanned: result.elementsScanned,
                passingElements: result.elementsScanned,
                elements: []
            )
            saveGTXResultAsYAML(passingResult, to: snapshotPath)
        }
        return nil
    }

    let rawError = result.aggregatedError().localizedDescription

    // Build a map of element addresses to their full text (first 50 chars)
    let elementTextMap = buildElementTextMap(from: view)

    let formattedResult = formatGTXResultWithMetadata(
        fromString: rawError,
        style: style,
        elementsScanned: result.elementsScanned,
        showPassingSummary: showPassingSummary,
        elementTextMap: elementTextMap
    )

    if let snapshotPath = snapshotPath {
        saveGTXResultAsYAML(formattedResult, to: snapshotPath)

        // Save numbered screenshot if requested
        if saveScreenshot {
            let failingElements = extractFailingElements(from: view, using: elementTextMap, result: result)
            if let screenshot = createScreenshotWithOverlays(view: view, failingElements: failingElements) {
                let screenshotPath = snapshotPath.replacingOccurrences(of: ".yml", with: "_screenshot.png")
                if let imageData = screenshot.pngData() {
                    try? imageData.write(to: URL(fileURLWithPath: screenshotPath))
                    print("📸 GTX screenshot with numbered overlays saved to: \(screenshotPath)")
                }
            }
        }
    }

    return formattedResult.formattedMessage
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
    guard !result.allChecksPassed() else {
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
    let errorString = result.aggregatedError().localizedDescription
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
            totalChecksPassed: 0,
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
    case .compact, .yaml:
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

    if result.allChecksPassed() {
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
    let errorString = result.aggregatedError().localizedDescription
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

// MARK: - YAML Export and Screenshot Support

private func buildElementTextMap(from rootView: UIView) -> [String: String] {
    var textMap: [String: String] = [:]

    func traverse(_ view: UIView) {
        let address = String(format: "%p", unsafeBitCast(view, to: Int.self))

        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            let truncated = String(text.prefix(50))
            textMap[address] = truncated
        } else if let button = view as? UIButton, let title = button.title(for: .normal), !title.isEmpty {
            let truncated = String(title.prefix(50))
            textMap[address] = truncated
        } else if let button = view as? UIButton, let attributedTitle = button.attributedTitle(for: .normal), !attributedTitle.string.isEmpty {
            let truncated = String(attributedTitle.string.prefix(50))
            textMap[address] = truncated
        }

        for subview in view.subviews {
            traverse(subview)
        }
    }

    traverse(rootView)
    return textMap
}

private func extractFailingElements(from rootView: UIView, using textMap: [String: String], result: GTXResult) -> [Any] {
    var failingElements: [Any] = []
    var elementAddresses: [String] = []

    // Extract addresses from error descriptions
    for error in result.errorsFound {
        let errorString = error.localizedDescription
        if let addressMatch = errorString.range(of: #"0x[0-9a-fA-F]+"#, options: .regularExpression) {
            let address = String(errorString[addressMatch])
            if !elementAddresses.contains(address) {
                elementAddresses.append(address)
            }
        }
    }

    // Find the actual view objects by traversing hierarchy
    func traverse(_ view: UIView) {
        let address = String(format: "%p", unsafeBitCast(view, to: Int.self))
        if elementAddresses.contains(address) {
            failingElements.append(view)
        }
        for subview in view.subviews {
            traverse(subview)
        }
    }

    traverse(rootView)
    return failingElements
}

private func createScreenshotWithOverlays(view: UIView, failingElements: [Any]) -> UIImage? {
    // Ensure the view has been laid out
    view.layoutIfNeeded()

    // Get the view's size
    let bounds = view.bounds
    guard bounds.width > 0, bounds.height > 0 else {
        print("⚠️ View has zero size, cannot create screenshot")
        return nil
    }

    // Create a graphics context
    UIGraphicsBeginImageContextWithOptions(bounds.size, false, UIScreen.main.scale)
    guard let context = UIGraphicsGetCurrentContext() else {
        print("⚠️ Could not create graphics context")
        return nil
    }

    // Render the view hierarchy into the context
    view.layer.render(in: context)

    // Draw numbered overlays for each failing element
    for (index, element) in failingElements.enumerated() {
        guard let failingView = element as? UIView else { continue }

        // Convert the failing view's frame to the root view's coordinate system
        let rect = failingView.convert(failingView.bounds, to: view)

        // Draw orange rectangle with thicker line
        context.setStrokeColor(UIColor.orange.cgColor)
        context.setLineWidth(3.0)
        context.stroke(rect)

        // Draw number label
        let numberLabel = "\(index + 1)"
        let fontSize: CGFloat = 16
        let font = UIFont.boldSystemFont(ofSize: fontSize)

        // Calculate text size
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let textSize = (numberLabel as NSString).size(withAttributes: textAttributes)

        // Position the number - alternate between corners
        let padding: CGFloat = 4
        let labelWidth = textSize.width + padding * 2
        let labelHeight = textSize.height + padding * 2

        // Alternate positions: top-left, top-right only (simpler pattern to avoid overlap)
        let position = index % 2
        let labelX: CGFloat
        let labelY: CGFloat

        if position == 0 {
            // Top-left (overlapping inside)
            labelX = max(0, rect.origin.x)
            labelY = max(0, rect.origin.y)
        } else {
            // Top-right (overlapping inside)
            labelX = min(bounds.width - labelWidth, rect.maxX - labelWidth)
            labelY = max(0, rect.origin.y)
        }

        let labelRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)

        // Draw orange background for the number
        context.setFillColor(UIColor.orange.cgColor)
        context.fill(labelRect)

        // Draw the number text
        let textRect = CGRect(x: labelX + padding, y: labelY + padding,
                            width: textSize.width, height: textSize.height)
        (numberLabel as NSString).draw(in: textRect, withAttributes: textAttributes)
    }

    // Get the rendered image
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image
}

private struct GTXElementWithText {
    let view: String
    let baseClass: String?
    let frameRect: String?
    let elementSize: String?
    let accessibilityFrame: String?
    let text: String?
    let checks: [GTXCheck]
}

private struct GTXFormattedResultWithText {
    let elementCount: Int
    let totalCheckFailures: Int
    let formattedMessage: String
    let hasFailures: Bool
    let elementsScanned: Int
    let passingElements: Int
    let elements: [(view: String, baseClass: String?, frameRect: String?,
                   elementSize: String?, accessibilityFrame: String?, text: String?,
                   checks: [(name: String, passed: Bool, reason: String?)])]
}

private func formatGTXResultWithMetadata(fromString raw: String, style: GTXAggregateStyle,
                                        elementsScanned: Int = 0, showPassingSummary: Bool = false,
                                        elementTextMap: [String: String] = [:]) -> GTXFormattedResultWithText {
    let elements = parseGTXElementsWithText(from: raw, elementTextMap: elementTextMap)

    guard !elements.isEmpty else {
        return GTXFormattedResultWithText(
            elementCount: 0,
            totalCheckFailures: 0,
            formattedMessage: "No GTX failures",
            hasFailures: false,
            elementsScanned: elementsScanned,
            passingElements: elementsScanned,
            elements: []
        )
    }

    // Don't group - keep each element separate as GTX reports them
    let grouped: [(elem: GTXElementWithText, checks: [GTXCheck])] = elements.map { ($0, $0.checks) }
    let totalCheckFailures = elements.reduce(0) { $0 + $1.checks.count }

    var message: String
    switch style {
    case .yaml:
        message = formatYAML(grouped, totalChecks: totalCheckFailures, elementsScanned: elementsScanned)
    case .rust:
        message = formatRustWithText(grouped, totalChecks: totalCheckFailures)
    case .compact, .arrows:
        message = formatCompactWithText(grouped, totalChecks: totalCheckFailures)
    }

    // Add passing summary if requested (but not for YAML style)
    if showPassingSummary && elementsScanned > 0 && style != .yaml {
        let elementsWithFailures = grouped.count
        let passingElements = elementsScanned - elementsWithFailures

        message += "\n\n" + """
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        📊 Summary:
           Total elements scanned: \(elementsScanned)
           ✅ Elements with no failures: \(passingElements)
           ❌ Elements with failures: \(elementsWithFailures)
           Total check failures: \(totalCheckFailures)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """
    }

    let publicElements = grouped.map { g in
        (view: g.elem.view, baseClass: g.elem.baseClass, frameRect: g.elem.frameRect,
         elementSize: g.elem.elementSize, accessibilityFrame: g.elem.accessibilityFrame, text: g.elem.text,
         checks: g.checks.map { (name: $0.name, passed: $0.passed, reason: $0.reason) })
    }

    let elementsWithFailures = grouped.count
    let passingElements = elementsScanned - elementsWithFailures

    return GTXFormattedResultWithText(
        elementCount: grouped.count,
        totalCheckFailures: totalCheckFailures,
        formattedMessage: message,
        hasFailures: true,
        elementsScanned: elementsScanned,
        passingElements: passingElements,
        elements: publicElements
    )
}

private func parseGTXElementsWithText(from raw: String, elementTextMap: [String: String]) -> [GTXElementWithText] {
    let normalizedLines = raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "UIExtendedSRGBColorSpace 1 1 1 1", with: "white")
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    var elements: [GTXElementWithText] = []
    var currentView: String?, currentBase: String?, currentFrameRect: String?
    var currentElemSize: String?, currentA11yFrame: String?, currentText: String?
    var currentElementAddress: String?
    var currentChecks: [GTXCheck] = []

    func flush() {
        guard let view = currentView else { return }

        // Try to get full text from the element map using the address
        var finalText = currentText
        if let address = currentElementAddress, let fullText = elementTextMap[address] {
            finalText = fullText
        }

        elements.append(GTXElementWithText(view: view, baseClass: currentBase, frameRect: currentFrameRect,
                                   elementSize: currentElemSize, accessibilityFrame: currentA11yFrame,
                                   text: finalText, checks: currentChecks))
        currentView = nil; currentBase = nil; currentFrameRect = nil
        currentElemSize = nil; currentA11yFrame = nil; currentText = nil
        currentElementAddress = nil; currentChecks = []
    }

    for line in normalizedLines {
        if line.hasPrefix("<"), line.contains(";"), line.contains(">") {
            flush()
            currentView = firstCapture(in: line, pattern: #"^<([^:>]+):"#)
                ?? firstCapture(in: line, pattern: #"^<([^>]+)>"#) ?? "UnknownView"
            currentBase = firstCapture(in: line, pattern: #"baseClass\s*=\s*([A-Za-z0-9_\.]+)"#)
            currentFrameRect = firstCapture(in: line, pattern: #"frame\s*=\s*\([^)]+\)"#)?
                .replacingOccurrences(of: "frame = ", with: "")

            // Extract element address: 0x107432550
            currentElementAddress = firstCapture(in: line, pattern: #":\s*(0x[0-9a-fA-F]+);"#)

            // Extract text for labels: text = 'Some Text' (length = 123)
            currentText = firstCapture(in: line, pattern: #"text\s*=\s*'([^']+)'"#)

            continue
        }
        if line.hasPrefix("+ Check ") || line.hasPrefix(" + Check ") {
            let checkName = firstCapture(in: line, pattern: #"\+ Check\s+"([^"]+)""#)
                ?? firstCapture(in: line, pattern: #"\+ Check\s+(.+?)\s+failed"#) ?? "Unknown check"
            let reason = firstCapture(in: line, pattern: #"failed,\s*(.*)$"#)?
                .trimmingCharacters(in: .whitespaces)
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

private func formatYAML(_ groups: [(elem: GTXElementWithText, checks: [GTXCheck])], totalChecks: Int, elementsScanned: Int) -> String {
    var yaml = ""

    // Failing elements section
    yaml += "failingElements:\n"
    for (index, g) in groups.enumerated() {
        let e = g.elem
        yaml += "  - id: \(index + 1)\n"
        yaml += "    view: \(yamlString(e.view))\n"
        if let text = e.text, !text.isEmpty {
            yaml += "    text: \(yamlString(text))\n"
        }
        if let baseClass = e.baseClass, !baseClass.isEmpty {
            yaml += "    baseClass: \(yamlString(baseClass))\n"
        }
        if let frameRect = e.frameRect, !frameRect.isEmpty {
            yaml += "    frameRect: \(yamlString(frameRect))\n"
        }
        if let elementSize = e.elementSize, !elementSize.isEmpty {
            yaml += "    elementSize: \(yamlString(elementSize))\n"
        }
        if let a11yFrame = e.accessibilityFrame, !a11yFrame.isEmpty, a11yFrame != "0x0" {
            yaml += "    accessibilityFrame: \(yamlString(a11yFrame))\n"
        }
        yaml += "    checks:\n"
        for c in g.checks {
            yaml += "      - name: \(yamlString(c.name))\n"
            yaml += "        reason: \(yamlString(c.reason ?? ""))\n"
        }
    }

    return yaml
}

private func formatRustWithText(_ groups: [(elem: GTXElementWithText, checks: [GTXCheck])], totalChecks: Int) -> String {
    var lines: [String] = []
    lines.append("GTXFailures { total: \(totalChecks), groups: [")
    for (idx, g) in groups.enumerated() {
        let e = g.elem
        lines.append("  // group #\(idx + 1)")
        lines.append("  GTXElement {")
        lines.append("    view: \"\(e.view)\",")
        if let text = e.text {
            lines.append("    text: \"\(text)\",")
        }
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

private func formatCompactWithText(_ groups: [(elem: GTXElementWithText, checks: [GTXCheck])], totalChecks: Int) -> String {
    var lines: [String] = []
    lines.append("GTX Failures: \(totalChecks)")
    for (idx, g) in groups.enumerated() {
        let e = g.elem
        var head = "(\(idx + 1)) \(e.view)"
        if let text = e.text {
            head += " text=\"\(text)\""
        }
        head += " [size=\(e.elementSize ?? "-"), frame=\(e.frameRect ?? "-")]"
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

private func yamlString(_ value: String) -> String {
    if value.isEmpty {
        return "\"\""
    }
    // Escape if contains special characters
    if value.contains("\"") || value.contains("\n") || value.contains(":") || value.contains("#") {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    return "\"\(value)\""
}

private func saveGTXResultAsYAML(_ result: GTXFormattedResultWithText, to path: String) {
    // Determine if path is a directory or file
    var isDirectory: ObjCBool = false
    let fileManager = FileManager.default
    let pathExists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

    let finalPath: String
    if pathExists && isDirectory.boolValue {
        // Path is a directory - append default filename
        let filename = "gtx_accessibility.yml"
        finalPath = (path as NSString).appendingPathComponent(filename)
    } else if path.hasSuffix(".yml") || path.hasSuffix(".yaml") {
        // Path is a specific file - use it directly
        finalPath = path
        // Create parent directory if needed
        let parentDir = (path as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: parentDir) {
            try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }
    } else {
        // Path doesn't exist and doesn't end in .yml/.yaml - treat as directory
        let filename = "gtx_accessibility.yml"
        try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        finalPath = (path as NSString).appendingPathComponent(filename)
    }

    // Build YAML manually
    var yaml = ""

    // Summary section
    yaml += "summary:\n"
    yaml += "  status: \(result.hasFailures ? "\"FAILED\"" : "\"PASSED\"")\n"
    yaml += "  elementsScanned: \(result.elementsScanned)\n"
    yaml += "  elementsWithFailures: \(result.elementCount)\n"
    yaml += "  totalCheckFailures: \(result.totalCheckFailures)\n"
    yaml += "\n"

    // Failing elements section
    if result.hasFailures {
        yaml += "failingElements:\n"
        for (index, element) in result.elements.enumerated() {
            yaml += "  - id: \(index + 1)\n"
            yaml += "    view: \(yamlString(element.view))\n"
            if let text = element.text, !text.isEmpty {
                yaml += "    text: \(yamlString(text))\n"
            }
            if let baseClass = element.baseClass, !baseClass.isEmpty {
                yaml += "    baseClass: \(yamlString(baseClass))\n"
            }
            if let frameRect = element.frameRect, !frameRect.isEmpty {
                yaml += "    frameRect: \(yamlString(frameRect))\n"
            }
            if let elementSize = element.elementSize, !elementSize.isEmpty {
                yaml += "    elementSize: \(yamlString(elementSize))\n"
            }
            if let a11yFrame = element.accessibilityFrame, !a11yFrame.isEmpty, a11yFrame != "0x0" {
                yaml += "    accessibilityFrame: \(yamlString(a11yFrame))\n"
            }
            yaml += "    checks:\n"
            for check in element.checks {
                yaml += "      - name: \(yamlString(check.name))\n"
                yaml += "        reason: \(yamlString(check.reason ?? ""))\n"
            }
        }
    } else {
        yaml += "failingElements: []\n"
    }

    do {
        try yaml.write(to: URL(fileURLWithPath: finalPath), atomically: true, encoding: .utf8)
        let statusIcon = result.hasFailures ? "⚠️" : "✅"
        print("\(statusIcon) GTX accessibility report saved to: \(finalPath)")
    } catch {
        print("⚠️ Failed to save GTX report to \(finalPath): \(error)")
    }
}

// MARK: - Test Helper

private func fail(_ message: String, file: String, line: UInt) {
    #if canImport(XCTest)
    XCTFail(message, file: StaticString(stringLiteral: file), line: line)
    #else
    assertionFailure(message)
    #endif
}
