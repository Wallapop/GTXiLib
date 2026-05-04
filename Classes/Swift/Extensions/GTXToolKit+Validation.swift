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

        print("Running GTX accessibility validation for: \(moduleName)")

        // Ensure view is fully laid out before validation
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Disable verbose GTX logging (those [GTX_LOG] messages)
        GTXLogger.default().setLogLevel(.silent)

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

        // Helper that materializes the overlay PNG + current-run YAML into a
        // destination directory. Used both for recording mode (writes to the
        // source reference directory) and for non-recording failures (writes
        // to a temp dir so Xcode can attach them without polluting the source
        // tree — which would trip Bazel's --guard_against_concurrent_changes).
        func writeDiagnostics(into directory: String,
                              yamlFilename: String,
                              pngFilename: String) -> (yaml: String?, png: String?) {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

            var writtenYAML: String?
            var writtenPNG: String?

            if formattedResult.hasFailures {
                let failingElements = extractFailingElements(from: view, using: elementTextMap, result: result)
                if let screenshot = createScreenshotWithOverlays(view: view,
                                                                 failingElements: failingElements,
                                                                 elementOrdering: orderingForOutput),
                   let imageData = screenshot.pngData()
                {
                    let dest = (directory as NSString).appendingPathComponent(pngFilename)
                    if (try? imageData.write(to: URL(fileURLWithPath: dest))) != nil {
                        writtenPNG = dest
                    }
                }
            }

            let yamlDest = (directory as NSString).appendingPathComponent(yamlFilename)
            let scratch = GTXAggregator(aggregatedYAMLPath: yamlDest)
            scratch.addTestResult(testName, result: formattedResult, screenshotName: pngFilename)
            if (try? scratch.save()) != nil {
                writtenYAML = yamlDest
            }
            return (writtenYAML, writtenPNG)
        }

        // In recording mode, write PNG + YAML to the source reference directory.
        if recordingMode {
            let yamlFilename = (yamlPath as NSString).lastPathComponent
            _ = writeDiagnostics(into: accessibilityDir, yamlFilename: yamlFilename, pngFilename: screenshotFilename)
            print("Results recorded to: \(yamlPath)")
            return nil
        }

        // Non-recording mode: compare NEW result against the saved YAML on disk.
        // Use an in-memory aggregator loaded from the existing file so we do NOT
        // write anything back to the source tree.
        let aggregator = GTXAggregator(aggregatedYAMLPath: yamlPath)
        aggregator.addTestResult(testName, result: formattedResult, screenshotName: screenshotFilename)
        let (contentMatches, diff) = aggregator.compareTestCase(testName)

        if contentMatches {
            print("Accessibility validation matches saved snapshot")
            return nil
        }

        let isNewTest = diff?.contains("does not exist") ?? false ||
            diff?.contains("not found in saved YAML") ?? false

        // Write diagnostics (PNG + current YAML) to a temp dir for attachment.
        let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("gtx-\(UUID().uuidString)")
        let tempYAMLFilename = (yamlPath as NSString).lastPathComponent
        let diagnostics = writeDiagnostics(into: tempDir,
                                           yamlFilename: tempYAMLFilename,
                                           pngFilename: screenshotFilename)

        if isNewTest {
            print("No reference found for \(testName). Run in recording mode to create one.")
        } else {
            print("Accessibility validation failed: Results differ from saved snapshot")
            if let diff { print(diff) }
            print("\n   Review the differences and either:")
            print("   1. Fix the accessibility issues, or")
            print("   2. Run tests in recording mode to accept the new results")
        }

        #if canImport(XCTest)
            addXCTestAttachments(yamlPath: diagnostics.yaml ?? yamlPath,
                                 screenshotPath: diagnostics.png ?? screenshotPath,
                                 diff: diff,
                                 formattedResult: formattedResult)
        #endif

        if isNewTest {
            return "Recorded new accessibility snapshot"
        }
        return "Accessibility snapshot mismatch - see \(yamlPath)"
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
    /// Adds XCTest attachments for accessibility snapshot mismatches.
    /// - Parameters:
    ///   - yamlPath: Path to the current-run YAML report (may be a temp path).
    ///   - screenshotPath: Path to the overlay screenshot (may be a temp path).
    ///   - diff: The textual diff between saved and current YAML, if available.
    ///   - formattedResult: The formatted result containing failure counts.
    private func addXCTestAttachments(yamlPath: String,
                                      screenshotPath: String,
                                      diff: String?,
                                      formattedResult: GTXFormattedResult) {
        let environment = ProcessInfo.processInfo.environment
        guard environment.keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS") ||
            environment.keys.contains("XCTestConfigurationFilePath")
        else {
            return
        }

        XCTContext.runActivity(named: "GTX Accessibility Failure") { activity in
            if let diff {
                let diffAttachment = XCTAttachment(string: diff)
                diffAttachment.name = "❌ GTX Accessibility Diff"
                diffAttachment.lifetime = .keepAlways
                activity.add(diffAttachment)
            }

            if FileManager.default.fileExists(atPath: yamlPath) {
                let yamlAttachment = XCTAttachment(contentsOfFile: URL(fileURLWithPath: yamlPath))
                yamlAttachment.name = "❌ GTX Current YAML"
                yamlAttachment.lifetime = .keepAlways
                activity.add(yamlAttachment)
            }

            if FileManager.default.fileExists(atPath: screenshotPath) {
                let screenshotAttachment = XCTAttachment(contentsOfFile: URL(fileURLWithPath: screenshotPath))
                screenshotAttachment.name = "❌ GTX Screenshot (\(formattedResult.elementCount) failing elements, \(formattedResult.totalCheckFailures) check failures)"
                screenshotAttachment.lifetime = .keepAlways
                activity.add(screenshotAttachment)
            }
        }
    }
#endif
