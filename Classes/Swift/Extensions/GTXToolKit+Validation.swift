//
//  GTXToolKit+Validation.swift
//  GTXiLib
//
//  Extension to GTXToolKit for aggregated accessibility validation
//

import Foundation
import UIKit
import GTXiLib
#if canImport(XCTest)
    import XCTest
#endif

// MARK: - GTXToolKit Extension for Validation and Aggregation

public extension GTXToolKit {
    /// Validates accessibility and aggregates results into YAML reports
    ///
    /// This method performs GTX accessibility validation on a view and saves the results
    /// to an aggregated YAML file along with screenshots of any failing elements.
    /// Uses GTXAggregator to properly collect results from multiple snapshots into a single file.
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

        // Extract just the screenshot filename (not full path) for YAML reference
        let screenshotFilename = (screenshotPath as NSString).lastPathComponent

        print("📸 Running GTX accessibility validation for: \(moduleName)")

        // Ensure view is fully laid out before validation
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Disable verbose GTX logging (those [GTX_LOG Error] messages)
        GTXLogger.default().setLogLevel(.warning)

        // Perform GTX accessibility validation
        let result = resultFromCheckingAllElements(fromRootElements: [view])

        // Build element ordering for consistent IDs
        let (elementOrdering, elementTextMap, addressMap) = buildElementOrderingAndTextMap(from: view)
        let failingOrdering = buildFailingOrdering(result: result,
                                                   elementOrdering: elementOrdering,
                                                   addressMap: addressMap)
        let orderingForOutput = failingOrdering.isEmpty ? elementOrdering : failingOrdering

        // Format the result with metadata
        let formattedResult: GTXFormattedResult
        if result.allChecksPassed() {
            formattedResult = GTXFormattedResult(
                elementCount: 0,
                totalCheckFailures: 0,
                totalChecksPassed: result.elementsScanned,
                formattedMessage: "All GTX checks passed",
                hasFailures: false,
                elements: []
            )
        } else {
            let rawError = result.aggregatedError().localizedDescription
            formattedResult = formatGTXResultWithMetadataForAggregation(
                fromString: rawError,
                elementsScanned: result.elementsScanned,
                elementTextMap: elementTextMap,
                elementOrdering: orderingForOutput,
                addressMap: addressMap
            )
        }

        // Generate screenshot if there are failures
        if formattedResult.hasFailures {
            let failingElements = extractFailingElements(from: view, using: elementTextMap, result: result)
            if let screenshot = createScreenshotWithOverlays(view: view,
                                                             failingElements: failingElements,
                                                             elementOrdering: orderingForOutput)
            {
                let parentDir = (screenshotPath as NSString).deletingLastPathComponent
                if !FileManager.default.fileExists(atPath: parentDir) {
                    try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                }

                if let imageData = screenshot.pngData() {
                    try? imageData.write(to: URL(fileURLWithPath: screenshotPath))
                    print("📸 GTX screenshot with numbered overlays saved to: \(screenshotPath)")
                }
            }
        }

        // Initialize aggregator and check what's saved
        let aggregator = GTXAggregator(aggregatedYAMLPath: yamlPath)

        // In recording mode, just add and save without comparing
        if recordingMode {
            aggregator.addTestResult(testName, result: formattedResult, screenshotName: screenshotFilename)
            do {
                try aggregator.save()
                print("📝 Results recorded to: \(yamlPath)")
            } catch {
                print("⚠️ Failed to save aggregated YAML: \(error)")
                return "Failed to save aggregated YAML: \(error)"
            }
            return nil
        }

        // Normal mode: Compare NEW result with saved test case
        // First, temporarily add to create a comparable state
        aggregator.addTestResult(testName, result: formattedResult, screenshotName: screenshotFilename)
        let (contentMatches, diff) = aggregator.compareTestCase(testName)

        if contentMatches {
            // Test case matches - don't write anything, just pass
            print("✅ Accessibility validation matches saved snapshot")
            return nil
        } else {
            // Check if this is a new test (file or test case doesn't exist)
            let isNewTest = diff?.contains("does not exist") ?? false ||
                diff?.contains("not found in saved YAML") ?? false

            // Save the new/updated content
            do {
                try aggregator.save()

                if isNewTest {
                    // New test - save and fail (standard snapshot behavior)
                    print("📝 New accessibility snapshot recorded to: \(yamlPath)")
                    print("   No reference was found. Automatically saved a new reference.")
                    print("   Re-run tests to compare against this reference.")
                    return "Recorded new accessibility snapshot"
                } else {
                    // Existing test with differences - fail
                    print("❌ Accessibility validation failed: Results differ from saved snapshot")
                    print("   Updated report saved to: \(yamlPath)")

                    // Print the diff to help debug
                    if let diff = diff {
                        print(diff)
                    }

                    print("\n   Review the differences and either:")
                    print("   1. Fix the accessibility issues, or")
                    print("   2. Run tests in recording mode to accept the new results")

                    #if canImport(XCTest)
                        // Add XCTest attachments for mismatch
                        addXCTestAttachments(yamlPath: yamlPath, screenshotPath: screenshotPath, formattedResult: formattedResult)
                    #endif

                    return "Accessibility snapshot mismatch - see \(yamlPath)"
                }
            } catch {
                print("⚠️ Failed to save aggregated YAML: \(error)")
                return "Failed to save aggregated YAML: \(error)"
            }
        }
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

// MARK: - XCTest Attachment Helper

#if canImport(XCTest)
    /// Adds XCTest attachments for accessibility snapshot mismatches
    /// - Parameters:
    ///   - yamlPath: Path to the YAML report file
    ///   - screenshotPath: Path to the screenshot file
    ///   - formattedResult: The formatted result containing failure details
    private func addXCTestAttachments(yamlPath: String, screenshotPath: String, formattedResult: GTXFormattedResult) {
        // Check if running in Xcode test environment
        let environment = ProcessInfo.processInfo.environment
        guard environment.keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS") ||
            environment.keys.contains("XCTestConfigurationFilePath")
        else {
            return
        }

        // Attach YAML report
        if FileManager.default.fileExists(atPath: yamlPath) {
            let yamlAttachment = XCTAttachment(contentsOfFile: URL(fileURLWithPath: yamlPath))
            yamlAttachment.name = "❌ FAILED - GTX Accessibility Report"
            yamlAttachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "GTX Accessibility Report") { activity in
                activity.add(yamlAttachment)
            }
        }

        // Attach screenshot (if it exists)
        if FileManager.default.fileExists(atPath: screenshotPath) {
            let screenshotAttachment = XCTAttachment(contentsOfFile: URL(fileURLWithPath: screenshotPath))
            screenshotAttachment.name = "❌ GTX Screenshot (\(formattedResult.elementCount) failing elements, \(formattedResult.totalCheckFailures) check failures)"
            screenshotAttachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "GTX Screenshot") { activity in
                activity.add(screenshotAttachment)
            }
        }
    }
#endif
