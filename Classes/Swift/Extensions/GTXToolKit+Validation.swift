//
//  GTXToolKit+Validation.swift
//  GTXiLib
//
//  Extension to GTXToolKit for aggregated accessibility validation
//

import Foundation
import UIKit

// MARK: - GTXToolKit Extension for Validation and Aggregation

public extension GTXToolKit {
    /// Validates accessibility and aggregates results into YAML reports
    ///
    /// This method performs GTX accessibility validation on a view and saves the results
    /// to an aggregated YAML file along with screenshots of any failing elements.
    ///
    /// - Parameters:
    ///   - view: The view to validate for accessibility
    ///   - testName: Name of the test being run
    ///   - moduleName: Name of the module (used for YAML file naming)
    ///   - baseDirectory: Base directory for storing validation results
    ///   - recordingMode: If true, validation issues are recorded but don't fail the test
    ///   - fileManager: Optional custom file manager (defaults to DefaultGTXSnapshotFileManager)
    ///   - directoryManager: Optional custom directory manager (defaults to DefaultGTXSnapshotDirectoryManager)
    /// - Returns: Error message if validation failed (nil in recording mode or if passed)
    func validateAndAggregate(
        view: UIView,
        testName: String,
        moduleName: String,
        baseDirectory: String,
        recordingMode: Bool,
        fileManager: GTXSnapshotFileManaging? = nil,
        directoryManager: GTXSnapshotDirectoryManaging? = nil
    ) -> String? {
        let fileMgr = fileManager ?? DefaultGTXSnapshotFileManager()
        let dirMgr = directoryManager ?? DefaultGTXSnapshotDirectoryManager()

        // Create accessibility directory
        guard let accessibilityDir = try? dirMgr.createAccessibilityDirectory(
            baseDirectory: baseDirectory
        ) else {
            return "Failed to create accessibility directory at: \(baseDirectory)"
        }

        // Resolve paths for screenshot and YAML
        let screenshotPath = dirMgr.screenshotPath(
            in: accessibilityDir,
            testName: testName
        )
        let yamlPath = dirMgr.aggregatedYAMLPath(
            in: accessibilityDir,
            moduleName: moduleName
        )

        // Log validation details
        print("📸 Running GTX accessibility validation...")
        print("   Test: \(testName)")
        print("   Module: \(moduleName)")
        print("   Screenshot: \(screenshotPath)")
        print("   YAML Report: \(yamlPath)")

        // Ensure view is fully laid out before validation
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Perform GTX accessibility validation
        // This calls the existing verifyAccessibility function from GTXiLib
        let accessibilityError = verifyAccessibility(
            checking: view,
            toolkit: self,
            style: .yaml,
            record: yamlPath,
            showPassingSummary: true,
            saveScreenshot: true,
            screenshotPath: screenshotPath
        )

        // Handle recording mode: log issues but don't fail the test
        if recordingMode, let error = accessibilityError {
            print("⚠️ Accessibility issues found (recording mode - test will not fail):")
            print("   \(error)")
            print("   Results saved to: \(yamlPath)")
            return nil // Don't fail in recording mode
        }

        // In normal mode, return any error to fail the test
        if let error = accessibilityError {
            print("❌ Accessibility validation failed:")
            print("   \(error)")
            print("   See report: \(yamlPath)")
        } else {
            print("✅ Accessibility validation passed")
        }

        return accessibilityError
    }

    /// Convenience method without custom managers
    @objc func validateAndAggregate(
        view: UIView,
        testName: String,
        moduleName: String,
        baseDirectory: String,
        recordingMode: Bool
    ) -> String? {
        return validateAndAggregate(
            view: view,
            testName: testName,
            moduleName: moduleName,
            baseDirectory: baseDirectory,
            recordingMode: recordingMode,
            fileManager: nil,
            directoryManager: nil
        )
    }
}