# GTX Result Formatting API

This document describes the Swift API for formatting and handling GTX accessibility check results.

## Overview

The library now provides a clean Swift API that takes UIView as input and handles GTX checks automatically:

1. **`formatGTXResult(checking:)`** - NEW: Run checks on a view and return structured result
2. **`failGTXAggregated(checking:)`** - Run checks on a view and fail immediately if issues found
3. **`assertGTXSnapshot(checking:)`** - NEW: Snapshot testing integration (requires swift-snapshot-testing)

For backward compatibility, string-based versions are also available with the `fromString:` parameter.

## API Reference

### GTXFormattedResult

A structured result type containing parsed GTX failures:

```swift
public struct GTXFormattedResult {
    public let elementCount: Int
    public let totalCheckFailures: Int
    public let formattedMessage: String
    public let hasFailures: Bool
    public let elements: [(view: String, baseClass: String?, frameRect: String?,
                          elementSize: String?, accessibilityFrame: String?,
                          checks: [(name: String, reason: String?)])]
}
```

### formatGTXResult(checking:)

Run GTX checks on a view and return formatted results without failing:

```swift
public func formatGTXResult(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true
) -> GTXFormattedResult
```

**Parameters:**
- `view`: UIView to check for accessibility issues
- `toolkit`: GTXToolKit instance to use (default: all default checks)
- `style`: Output format style (`.compact`, `.arrows`, or `.rust`)
- `deduplicate`: Remove duplicate failures (default: `true`)

**Returns:** `GTXFormattedResult` with parsed and formatted data

### formatGTXResult(fromString:)

Parse and format GTX results from a raw error string:

```swift
public func formatGTXResult(
    fromString raw: String,
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true
) -> GTXFormattedResult
```

**Parameters:**
- `raw`: Raw GTX error output string
- `style`: Output format style (`.compact`, `.arrows`, or `.rust`)
- `deduplicate`: Remove duplicate failures (default: `true`)

**Returns:** `GTXFormattedResult` with parsed and formatted data

### failGTXAggregated(checking:)

Run GTX checks on a view and fail immediately if issues are found:

```swift
public func failGTXAggregated(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    file: String = #file,
    line: UInt = #line
)
```

### failGTXAggregated(fromString:)

Parse a raw GTX error string and fail immediately:

```swift
public func failGTXAggregated(
    fromString raw: String,
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    file: String = #file,
    line: UInt = #line
)
```

### assertGTXSnapshot(checking:)

Snapshot testing helper for views (requires swift-snapshot-testing):

```swift
public func assertGTXSnapshot(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    recording: Bool = false,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
)
```

### assertGTXSnapshot(fromString:)

Snapshot testing helper for raw strings (requires swift-snapshot-testing):

```swift
public func assertGTXSnapshot(
    fromString raw: String,
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    recording: Bool = false,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
)
```

## Usage Examples

### Example 1: Custom Logging

```swift
func testAccessibilityWithLogging() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        let formatted = formatGTXResult(from: errorString, style: .compact)

        // Log to analytics
        analytics.logAccessibilityIssues(count: formatted.totalCheckFailures)

        // Print detailed report
        print(formatted.formattedMessage)

        // Fail test with count
        XCTFail("Found \(formatted.totalCheckFailures) accessibility issues across \(formatted.elementCount) elements")
    }
}
```

### Example 2: Conditional Failing

```swift
func testAccessibilityWithThreshold() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        let formatted = formatGTXResult(from: errorString)

        // Only fail if more than 5 issues
        if formatted.totalCheckFailures > 5 {
            fail(formatted.formattedMessage)
        } else {
            print("⚠️ Found \(formatted.totalCheckFailures) minor issues (below threshold)")
        }
    }
}
```

### Example 3: Programmatic Analysis

```swift
func testAccessibilityWithAnalysis() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        let formatted = formatGTXResult(from: errorString)

        // Analyze specific check types
        var contrastIssues = 0
        var tapTargetIssues = 0

        for element in formatted.elements {
            for check in element.checks {
                if check.name.contains("contrast") {
                    contrastIssues += 1
                } else if check.name.contains("minimum size") {
                    tapTargetIssues += 1
                }
            }
        }

        print("Contrast issues: \(contrastIssues)")
        print("Tap target issues: \(tapTargetIssues)")

        XCTAssertEqual(contrastIssues, 0, "Found contrast issues")
        XCTAssertEqual(tapTargetIssues, 0, "Found tap target issues")
    }
}
```

### Example 4: Snapshot Testing

First, add swift-snapshot-testing to your Package.swift or Podfile:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0")
]
```

Then use in tests:

```swift
import SnapshotTesting

func testAccessibilitySnapshot() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        // Will create/compare against __Snapshots__/testAccessibilitySnapshot.txt
        assertGTXSnapshot(errorString, style: .compact)
    }
}

func testAccessibilitySnapshotRecording() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        // Record new snapshot
        assertGTXSnapshot(errorString, recording: true)
    }
}
```

### Example 5: Different Output Styles

```swift
let errorString = """
<UIButton: 0x123; baseClass = UIControl; frame = (10, 20, 30, 40)>
+ Check "Minimum tap target size" failed, Element has insufficient size
Element frame: {{10, 20}, {30, 40}}
"""

// Compact style (default)
let compact = formatGTXResult(from: errorString, style: .compact)
print(compact.formattedMessage)
// Output:
// GTX Failures: 1
// (1) UIButton [size={{10, 20}, {30, 40}}, frame=(10, 20, 30, 40)]
//   - Minimum tap target size: failed — Element has insufficient size

// Arrow style
let arrows = formatGTXResult(from: errorString, style: .arrows)
print(arrows.formattedMessage)
// Output:
// ╭──▶ GTX Failures (count: 1)
// ────▶ Element #1 – UIButton
//      ╭──▶ base_class: UIControl
//      ├──▶ element_size: {{10, 20}, {30, 40}}
//      ├──▶ frame: (10, 20, 30, 40)
//      ╭──▶ checks (1)
//          ────▶ [Minimum tap target size] ❌ failed — Element has insufficient size
//      ╰─╮ end-checks
// ╰──▶ end

// Rust style
let rust = formatGTXResult(from: errorString, style: .rust)
print(rust.formattedMessage)
// Output:
// GTXFailures { total: 1, groups: [
//   // group #1
//   GTXElement {
//     view: "UIButton",
//     base_class: "UIControl",
//     frame: "(10, 20, 30, 40)",
//     element_size: "{{10, 20}, {30, 40}}",
//     accessibility_frame: None,
//     checks: [
//       GTXCheck { name: "Minimum tap target size", result: "failed", reason: "Element has insufficient size" },
//     ]
//   },
// ] }
```

### Example 6: Integration with Existing API

```swift
// Old way (still works)
func testAccessibilityOldWay() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        failGTXAggregated(from: errorString)  // Fails immediately
    }
}

// New way with more control
func testAccessibilityNewWay() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: rootElement, error: &error)

    if !result, let errorString = error?.localizedDescription {
        let formatted = formatGTXResult(from: errorString)

        // Do custom processing
        logToAnalytics(formatted)

        // Then fail if needed
        if formatted.hasFailures {
            XCTFail(formatted.formattedMessage)
        }
    }
}
```

## Format Style Comparison

| Style | Best For | Pros | Cons |
|-------|----------|------|------|
| `.compact` | CI/CD logs, quick reviews | Concise, easy to scan | Less visual structure |
| `.arrows` | Detailed debugging | Clear hierarchy, visual flow | Verbose for many failures |
| `.rust` | IDE integration, parsing | Machine-readable structure | Less human-friendly |

## Snapshot Testing Setup

1. Add swift-snapshot-testing to your project:

```ruby
# Podfile
pod 'SnapshotTesting', '~> 1.12.0'
```

2. Import in your test file:

```swift
import SnapshotTesting
```

3. Use `assertGTXSnapshot()` instead of `failGTXAggregated()`:

```swift
func testMyView() {
    var error: NSError?
    let result = GTXiLib.checkAllElements(from: myView, error: &error)

    if !result, let errorString = error?.localizedDescription {
        assertGTXSnapshot(errorString)
    }
}
```

4. Run tests to generate snapshots:
   - First run: Creates snapshot files in `__Snapshots__/`
   - Subsequent runs: Compares against saved snapshots
   - To update snapshots: Set `recording: true`

## Migration Guide

### From error reference pattern:

```swift
// Before
var error: NSError?
let result = GTXiLib.checkAllElements(from: view, error: &error)
if !result {
    XCTFail(error?.localizedDescription ?? "GTX check failed")
}

// After (with formatting)
var error: NSError?
let result = GTXiLib.checkAllElements(from: view, error: &error)
if !result, let errorString = error?.localizedDescription {
    failGTXAggregated(from: errorString)  // One-line formatted failure
}

// Or (with custom handling)
var error: NSError?
let result = GTXiLib.checkAllElements(from: view, error: &error)
if !result, let errorString = error?.localizedDescription {
    let formatted = formatGTXResult(from: errorString)
    // Custom logic here
    XCTFail(formatted.formattedMessage)
}
```

## Best Practices

1. **Use `formatGTXResult()` when you need**:
   - Custom failure logic
   - Analytics/logging
   - Programmatic analysis
   - Conditional assertions

2. **Use `failGTXAggregated()` when you need**:
   - Simple, immediate test failure
   - Standard XCTest integration
   - No custom processing

3. **Use `assertGTXSnapshot()` when you need**:
   - Regression testing
   - Documentation of accessibility state
   - Visual approval workflow
   - CI/CD snapshot comparison

4. **Deduplication**: Keep enabled (default) unless you specifically need to count repeated failures

5. **Style Selection**:
   - Local development: `.arrows` (most readable)
   - CI/CD: `.compact` (concise logs)
   - Tooling/automation: `.rust` (parseable)
