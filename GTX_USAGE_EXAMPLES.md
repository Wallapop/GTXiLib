# GTX Swift API Usage Examples

## Quick Start - New Simple API

The new API takes a `UIView` directly - no need to deal with error references!

```swift
func testAccessibility() {
    let myView = createMyView()

    // Simple one-liner - runs all default checks and fails if issues found
    failGTXAggregated(checking: myView)
}
```

## Example 1: Custom Logging

```swift
func testAccessibilityWithLogging() {
    let myView = createMyView()

    // Run checks and get structured result
    let result = formatGTXResult(checking: myView, style: .compact)

    if result.hasFailures {
        // Log to analytics
        analytics.logAccessibilityIssues(count: result.totalCheckFailures)

        // Print detailed report
        print(result.formattedMessage)

        // Fail test with count
        XCTFail("Found \(result.totalCheckFailures) accessibility issues across \(result.elementCount) elements")
    }
}
```

## Example 2: Conditional Failing Based on Threshold

```swift
func testAccessibilityWithThreshold() {
    let myView = createMyView()

    let result = formatGTXResult(checking: myView)

    // Only fail if more than 5 issues
    if result.totalCheckFailures > 5 {
        XCTFail(result.formattedMessage)
    } else if result.hasFailures {
        print("⚠️ Found \(result.totalCheckFailures) minor issues (below threshold)")
    }
}
```

## Example 3: Programmatic Analysis of Specific Check Types

```swift
func testAccessibilityWithAnalysis() {
    let myView = createMyView()

    let result = formatGTXResult(checking: myView)

    // Analyze specific check types
    var contrastIssues = 0
    var tapTargetIssues = 0

    for element in result.elements {
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
```

## Example 4: Custom Toolkit with Specific Checks

```swift
func testAccessibilityWithCustomChecks() {
    let myView = createMyView()

    // Create custom toolkit with specific checks
    let toolkit = GTXToolKit.toolkitWithNoChecks()
    toolkit.registerCheck(GTXChecksCollection.checkForMinimumTappableArea())
    toolkit.registerCheck(GTXChecksCollection.checkForSufficientContrastRatio())

    // Run only these specific checks
    let result = formatGTXResult(checking: myView, toolkit: toolkit)

    if result.hasFailures {
        XCTFail(result.formattedMessage)
    }
}
```

## Example 5: Snapshot Testing

First, add swift-snapshot-testing to your Package.swift or Podfile:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0")
]
```

Or:

```ruby
# Podfile
pod 'SnapshotTesting', '~> 1.12.0'
```

Then use in tests:

```swift
import SnapshotTesting

func testAccessibilitySnapshot() {
    let myView = createMyView()

    // Will create/compare against __Snapshots__/testAccessibilitySnapshot.txt
    assertGTXSnapshot(checking: myView, style: .compact)
}

func testAccessibilitySnapshotRecording() {
    let myView = createMyView()

    // Record new snapshot
    assertGTXSnapshot(checking: myView, recording: true)
}
```

## Example 6: Different Output Styles

```swift
func testDifferentStyles() {
    let myView = UIButton(frame: CGRect(x: 10, y: 20, width: 30, height: 40))

    // Compact style (default) - best for CI/CD
    let compact = formatGTXResult(checking: myView, style: .compact)
    print(compact.formattedMessage)
    // Output:
    // GTX Failures: 1
    // (1) UIButton [size={{10, 20}, {30, 40}}, frame=(10, 20, 30, 40)]
    //   - Minimum tap target size: failed — Element has insufficient size

    // Arrow style - best for detailed debugging
    let arrows = formatGTXResult(checking: myView, style: .arrows)
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

    // Rust style - best for machine parsing
    let rust = formatGTXResult(checking: myView, style: .rust)
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
}
```

## Example 7: Multiple Views

```swift
func testMultipleViews() {
    let view1 = createView1()
    let view2 = createView2()

    // Check each view separately
    failGTXAggregated(checking: view1)
    failGTXAggregated(checking: view2)

    // Or combine results
    let result1 = formatGTXResult(checking: view1)
    let result2 = formatGTXResult(checking: view2)

    let totalIssues = result1.totalCheckFailures + result2.totalCheckFailures
    if totalIssues > 0 {
        XCTFail("Found \(totalIssues) total issues across both views")
    }
}
```

## Migration from Old API

### Before (error reference pattern):

```swift
var error: NSError?
let result = GTXiLib.checkAllElements(from: view, error: &error)
if !result {
    XCTFail(error?.localizedDescription ?? "GTX check failed")
}
```

### After (new view-based API):

```swift
// Simplest form
failGTXAggregated(checking: view)

// Or with formatted output
let result = formatGTXResult(checking: view)
if result.hasFailures {
    XCTFail(result.formattedMessage)
}
```

### If you still have error strings (backward compatibility):

```swift
// You can still use the fromString variant
var error: NSError?
let result = GTXiLib.checkAllElements(from: view, error: &error)
if !result, let errorString = error?.localizedDescription {
    failGTXAggregated(fromString: errorString)
}
```

## Best Practices

1. **Use `formatGTXResult(checking:)` when you need**:
   - Custom failure logic
   - Analytics/logging
   - Programmatic analysis
   - Conditional assertions

2. **Use `failGTXAggregated(checking:)` when you need**:
   - Simple, immediate test failure
   - Standard XCTest integration
   - No custom processing

3. **Use `assertGTXSnapshot(checking:)` when you need**:
   - Regression testing
   - Documentation of accessibility state
   - Visual approval workflow
   - CI/CD snapshot comparison

4. **Style Selection**:
   - Local development: `.arrows` (most readable)
   - CI/CD: `.compact` (concise logs)
   - Tooling/automation: `.rust` (parseable)

5. **Deduplication**: Keep enabled (default) unless you specifically need to count repeated failures
