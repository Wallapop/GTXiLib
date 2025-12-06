//
//  GTXSnapshotting.swift
//  GTXiLib
//
//  SnapshotTesting-style API for GTX accessibility validation
//

import Foundation
import UIKit
import GTXiLib

#if canImport(XCTest)
import XCTest
#endif

// MARK: - GTXSnapshotting Strategy

/// A snapshot strategy configuration for GTX accessibility checks
///
/// This provides a SnapshotTesting-compatible API for performing GTX accessibility validation.
/// It can be used as a drop-in replacement for visual snapshot testing libraries.
public struct GTXSnapshotting<Value, Format> {
    /// The snapshot function that performs the accessibility checks
    public let snapshot: (Value) -> Format

    /// Compares two snapshots for equality
    public let compare: (Format, Format) -> String?

    /// File extension for saved snapshots
    public let pathExtension: String?

    /// Initializes a new snapshot strategy
    public init(
        snapshot: @escaping (Value) -> Format,
        compare: @escaping (Format, Format) -> String?,
        pathExtension: String? = nil
    ) {
        self.snapshot = snapshot
        self.compare = compare
        self.pathExtension = pathExtension
    }
}

// MARK: - Accessibility Snapshot Value

/// Represents a captured accessibility snapshot of a view
public struct GTXAccessibilitySnapshot {
    /// The view being validated
    public let view: UIView

    /// The GTX toolkit used for validation
    public let toolkit: GTXToolKit

    /// The output style for formatting results
    public let style: GTXAggregateStyle

    /// Optional path to save YAML reports
    public let recordPath: String?

    /// Whether to save screenshots of failing elements
    public let saveScreenshot: Bool

    /// Optional custom path for screenshots
    public let screenshotPath: String?

    /// Whether to show passing elements in the summary
    public let showPassingSummary: Bool

    /// Whether to deduplicate identical failures
    public let deduplicate: Bool

    /// Initializes a new accessibility snapshot
    public init(
        view: UIView,
        toolkit: GTXToolKit,
        style: GTXAggregateStyle,
        recordPath: String? = nil,
        saveScreenshot: Bool = false,
        screenshotPath: String? = nil,
        showPassingSummary: Bool = true,
        deduplicate: Bool = true
    ) {
        self.view = view
        self.toolkit = toolkit
        self.style = style
        self.recordPath = recordPath
        self.saveScreenshot = saveScreenshot
        self.screenshotPath = screenshotPath
        self.showPassingSummary = showPassingSummary
        self.deduplicate = deduplicate
    }

    /// Performs the accessibility verification
    /// - Returns: Error message if validation failed, nil if passed
    public func verify() -> String? {
        // Ensure view is laid out
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Perform GTX validation
        return verifyAccessibility(
            checking: view,
            toolkit: toolkit,
            style: style,
            record: recordPath,
            showPassingSummary: showPassingSummary,
            saveScreenshot: saveScreenshot,
            screenshotPath: screenshotPath
        )
    }
}

// MARK: - UIView Snapshot Strategy

public extension GTXSnapshotting where Value == UIView, Format == GTXAccessibilitySnapshot {
    /// A default snapshot strategy for UIView accessibility validation
    static var accessibility: GTXSnapshotting {
        return .accessibility()
    }

    /// Creates a snapshot strategy for comparing views based on accessibility checks
    ///
    /// - Parameters:
    ///   - toolkit: The GTX toolkit to use for checking. Defaults to all default checks.
    ///   - style: The output style for formatting results (arrows, rust, compact, yaml).
    ///   - recordPath: Optional path to save YAML reports when recording mode is enabled.
    ///   - saveScreenshot: Whether to save numbered screenshots highlighting failing elements.
    ///   - screenshotPath: Optional custom path for the screenshot file.
    ///   - showPassingSummary: Whether to show a summary of passing elements alongside failures.
    ///   - deduplicate: Whether to deduplicate identical failures across elements.
    /// - Returns: A GTXSnapshotting strategy for accessibility validation
    static func accessibility(
        toolkit: GTXToolKit = .toolkitWithAllDefaultChecks(),
        style: GTXAggregateStyle = .compact,
        recordPath: String? = nil,
        saveScreenshot: Bool = false,
        screenshotPath: String? = nil,
        showPassingSummary: Bool = true,
        deduplicate: Bool = true
    ) -> GTXSnapshotting {
        return GTXSnapshotting(
            snapshot: { view in
                GTXAccessibilitySnapshot(
                    view: view,
                    toolkit: toolkit,
                    style: style,
                    recordPath: recordPath,
                    saveScreenshot: saveScreenshot,
                    screenshotPath: screenshotPath,
                    showPassingSummary: showPassingSummary,
                    deduplicate: deduplicate
                )
            },
            compare: { snapshot1, _ in
                // Run the checks and return error message if any
                snapshot1.verify()
            },
            pathExtension: "yml"
        )
    }
}

// MARK: - Public API Functions

/// Verifies a GTX accessibility snapshot for a given view
///
/// This function provides a SnapshotTesting-compatible API for GTX validation.
///
/// - Parameters:
///   - value: The view to validate
///   - snapshotting: The snapshot strategy to use
///   - recordPath: Optional path to save validation results
///   - saveScreenshot: Whether to save screenshots of failures
///   - screenshotPath: Optional custom screenshot path
/// - Returns: Error message if validation failed, nil if passed
public func verifyGTXSnapshot<Value, Format>(
    of value: Value,
    as snapshotting: GTXSnapshotting<Value, Format>,
    recordPath: String? = nil,
    saveScreenshot: Bool = false,
    screenshotPath: String? = nil
) -> String? {
    let snapshot = snapshotting.snapshot(value)
    return snapshotting.compare(snapshot, snapshot)
}

#if canImport(XCTest)
/// Asserts that a view passes GTX accessibility validation
///
/// This function integrates with XCTest to fail tests when accessibility issues are found.
///
/// - Parameters:
///   - value: The view to validate
///   - snapshotting: The snapshot strategy to use
///   - recordPath: Optional path to save validation results
///   - saveScreenshot: Whether to save screenshots of failures
///   - screenshotPath: Optional custom screenshot path
///   - file: The file where the assertion is made (for test failure reporting)
///   - testName: The name of the test (for test failure reporting)
///   - line: The line where the assertion is made (for test failure reporting)
public func assertGTXSnapshot<Value, Format>(
    of value: Value,
    as snapshotting: GTXSnapshotting<Value, Format>,
    recordPath: String? = nil,
    saveScreenshot: Bool = false,
    screenshotPath: String? = nil,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
) {
    if let error = verifyGTXSnapshot(
        of: value,
        as: snapshotting,
        recordPath: recordPath,
        saveScreenshot: saveScreenshot,
        screenshotPath: screenshotPath
    ) {
        XCTFail(
            "GTX accessibility validation failed:\n\(error)",
            file: file,
            line: line
        )
    }
}
#endif