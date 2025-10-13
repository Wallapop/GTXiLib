# GTX Swift API Usage Examples

## 1. Simple Verification (Returns Error Message)

Similar to snapshot testing API - returns `nil` if all checks pass, or error message if any fail.

```swift
import GTXiLib

func testAccessibility() {
    let view = createMyView()

    let errorMessage = verifyAccessibility(checking: view)
    if let errorMessage {
        XCTFail(errorMessage)
    }
}
```

**Or using Nimble:**

```swift
let errorMessage = verifyAccessibility(
    checking: view,
    toolkit: .toolkitWithAllDefaultChecks(),
    style: .rust
)
if let errorMessage {
    fail(errorMessage)
}
```

## 2. One-Liner Assertion

Use when you want immediate failure:

```swift
failGTXAggregated(checking: view)
```

With custom style:

```swift
failGTXAggregated(checking: view, toolkit: Self.toolkit, style: .rust)
```

## 3. Programmatic Result Handling

Use when you need custom logic based on results:

```swift
let result = formatGTXResult(checking: view)

if result.hasFailures {
    print("Found \(result.totalCheckFailures) issues")
    print(result.formattedMessage)
}
```

## 4. With Snapshot Testing Integration

```swift
func testMyView() {
    let view = createView()

    // Visual snapshot
    expect(view).to(validateSnapshot())

    // Accessibility verification
    let errorMessage = verifyAccessibility(checking: view, style: .compact)
    if let errorMessage {
        fail(errorMessage)
    }
}
```

## 5. Custom Toolkit

```swift
let toolkit = GTXToolKit.toolkitWithNoChecks()
toolkit.registerCheck(GTXChecksCollection.checkForMinimumTappableArea())

let errorMessage = verifyAccessibility(
    checking: view,
    toolkit: toolkit
)
```

## 6. Including Passing Checks Summary

```swift
let result = formatGTXResult(
    checking: view,
    includePassing: true  // Shows summary with pass/fail counts
)

print(result.formattedMessage)
// Output:
// GTX Failures: 2
// (1) UIButton [...]
//   ❌ Minimum tap target size: failed
//
// 📊 Summary: 2 failed, ~18 passed (20 elements)
```

## API Comparison

### Old API (Manual Error Handling)

```swift
var error: NSError?
let result = toolkit.checkAllElements(fromRootElements: [view], error: &error)
if !result {
    let errorString = error?.userInfo["NSLocalizedDescription"] as? String ?? ""
    // Manual parsing needed...
}
```

### New API Option 1: Returns Message (Like Snapshot Testing)

```swift
let errorMessage = verifyAccessibility(checking: view)
if let errorMessage {
    fail(errorMessage)
}
```

### New API Option 2: Immediate Fail

```swift
failGTXAggregated(checking: view)
```

### New API Option 3: Structured Result

```swift
let result = formatGTXResult(checking: view)
// Access: result.elementCount, result.totalCheckFailures, result.elements, etc.
```

## Complete Example with All Features

```swift
import GTXiLib
import Nimble
import Quick

class MyViewTests: QuickSpec {
    static let toolkit = GTXToolKit.toolkitWithAllDefaultChecks()

    override static func spec() {
        describe("MyView") {
            it("has valid snapshot and accessibility") {
                let view = MyView()
                view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)

                // Visual snapshot test
                expect(view).to(validateSnapshot())

                // Accessibility test - same pattern as snapshot
                let errorMessage = verifyAccessibility(
                    checking: view,
                    toolkit: Self.toolkit,
                    style: .compact
                )
                if let errorMessage {
                    fail(errorMessage)
                }
            }

            it("custom accessibility checks") {
                let view = MyComplexView()

                // Get structured result for custom logic
                let result = formatGTXResult(
                    checking: view,
                    includePassing: true
                )

                // Custom assertions
                expect(result.totalCheckFailures).to(beLessThan(3))

                if result.hasFailures {
                    print(result.formattedMessage)
                }
            }
        }
    }
}
```

## Public API Reference

### verifyAccessibility()

Returns error message if checks fail, nil if all pass.

```swift
public func verifyAccessibility(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    includePassing: Bool = false
) -> String?
```

### failGTXAggregated()

Fails test immediately if checks fail.

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

### formatGTXResult()

Returns structured result without failing.

```swift
public func formatGTXResult(
    checking view: UIView,
    toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
    style: GTXAggregateStyle = .compact,
    deduplicate: Bool = true,
    includePassing: Bool = false
) -> GTXFormattedResult
```

### GTXFormattedResult

```swift
public struct GTXFormattedResult {
    public let elementCount: Int
    public let totalCheckFailures: Int
    public let totalChecksPassed: Int
    public let formattedMessage: String
    public let hasFailures: Bool
    public let elements: [(view, baseClass, frameRect, elementSize, accessibilityFrame, checks)]
}
```

### GTXAggregateStyle

```swift
public enum GTXAggregateStyle {
    case arrows   // Unicode arrow-flow
    case rust     // Rust-like struct debug dump
    case compact  // Short list (default)
}
```
