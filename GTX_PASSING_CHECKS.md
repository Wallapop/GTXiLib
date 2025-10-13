# Documenting Passing Checks in GTX

## Overview

By default, GTX only reports **failures**. However, the `includePassing` parameter allows you to also see passing checks in your output.

## Usage

```swift
let result = formatGTXResult(
    checking: myView,
    includePassing: true  // <-- Add this parameter
)
```

## What Gets Included

When `includePassing: true`:

### Current Limitation

Due to GTXToolKit API limitations, we cannot track individual passing checks per element. Instead, the API provides:

- **Exact failure count**: Number of checks that failed
- **Estimated passing count**: `elementsScanned - failures`
- **Summary line**: Added to the formatted output

### Example Output

**Without `includePassing` (default)**:
```
GTX Failures: 2
(1) UIButton [size={{10, 20}, {30, 40}}, frame=(10, 20, 30, 40)]
  ❌ Minimum tap target size: failed — Element has insufficient size
(2) UILabel [size={{100, 100}, {200, 20}}, frame=(100, 100, 200, 20)]
  ❌ Accessible label: failed — Element has no accessibility label
```

**With `includePassing: true`**:
```
GTX Failures: 2
(1) UIButton [size={{10, 20}, {30, 40}}, frame=(10, 20, 30, 40)]
  ❌ Minimum tap target size: failed — Element has insufficient size
(2) UILabel [size={{100, 100}, {200, 20}}, frame=(100, 100, 200, 20)]
  ❌ Accessible label: failed — Element has no accessibility label

📊 Summary: 2 failed, ~18 passed (20 elements)
```

## Use Cases

### 1. Progress Tracking

```swift
func testAccessibilityProgress() {
    let result = formatGTXResult(checking: complexView, includePassing: true)

    print("Pass rate: \(result.totalChecksPassed)/\(result.totalChecksPassed + result.totalCheckFailures)")
    // Output: "Pass rate: 45/50"

    if result.hasFailures {
        print(result.formattedMessage)
    }
}
```

### 2. Snapshot Testing with Context

```swift
func testAccessibilitySnapshot() {
    // Include passing count in snapshot for context
    assertGTXSnapshot(checking: myView)  // Note: doesn't support includePassing yet

    // Or manually:
    let result = formatGTXResult(checking: myView, includePassing: true)
    // Save result.formattedMessage to snapshot
}
```

### 3. Reporting

```swift
func testAccessibilityReport() {
    let result = formatGTXResult(checking: rootView, includePassing: true)

    let report = """
    Accessibility Report
    ====================
    Elements Scanned: \(result.totalChecksPassed + result.totalCheckFailures)
    Checks Passed: \(result.totalChecksPassed)
    Checks Failed: \(result.totalCheckFailures)
    Pass Rate: \(String(format: "%.1f%%", Double(result.totalChecksPassed) / Double(result.totalChecksPassed + result.totalCheckFailures) * 100))

    \(result.formattedMessage)
    """

    print(report)
}
```

## Future Enhancement

To get **per-element passing checks**, GTXToolKit would need to expose:
- List of registered checks
- Access to the accessibility tree
- Ability to run checks individually and capture results

A full implementation would look like:

```swift
// FUTURE: Not currently possible without GTX API changes
for element in accessibilityTree {
    for check in toolkit.registeredChecks {
        let passed = check.run(on: element)
        if passed {
            results.append((element, check, .passed))
        } else {
            results.append((element, check, .failed(reason)))
        }
    }
}
```

## API Reference

### formatGTXResult(checking:includePassing:)

```swift
public func formatGTXResult(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    includePassing: Bool = false  // NEW parameter
) -> GTXFormattedResult
```

### GTXFormattedResult

```swift
public struct GTXFormattedResult {
    public let elementCount: Int
    public let totalCheckFailures: Int
    public let totalChecksPassed: Int        // NEW field
    public let formattedMessage: String
    public let hasFailures: Bool
    public let elements: [(
        view: String,
        baseClass: String?,
        frameRect: String?,
        elementSize: String?,
        accessibilityFrame: String?,
        checks: [(
            name: String,
            passed: Bool,                     // NEW field
            reason: String?
        )]
    )]
}
```

## Limitations

1. **Estimated count only**: `totalChecksPassed` is an estimate (elementsScanned - failures)
2. **No per-element passing details**: Cannot show which specific checks passed on each element
3. **Requires GTXToolKit API extension**: Full implementation would need changes to GTX core

## Workaround for Detailed Tracking

If you need detailed passing check information, you can:

1. Create a custom toolkit with specific checks
2. Run checks manually on each element
3. Track results yourself

```swift
let toolkit = GTXToolKit.toolkitWithNoChecks()
let checks = [
    GTXChecksCollection.checkForMinimumTappableArea(),
    GTXChecksCollection.checkForSufficientContrastRatio()
]
checks.forEach { toolkit.registerCheck($0) }

// Get all accessible elements manually
let elements = getAccessibleElements(from: myView)

var results: [(element: UIView, check: String, passed: Bool)] = []

for element in elements {
    for check in checks {
        var error: NSError?
        let passed = check.check(element, error: &error)
        results.append((element, check.name, passed))
    }
}

// Now you have full per-element, per-check tracking
```

## Best Practices

- **Use `includePassing: false` (default)** for regular test failures - focus on what's broken
- **Use `includePassing: true`** for reporting and progress tracking
- **Be aware** that the passing count is estimated, not exact
- For snapshot testing, the default (failures only) is usually better - you care about regressions, not the total state
