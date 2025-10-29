//
//  GTXSnapshotProtocols.swift
//  GTXiLib
//
//  Protocols for snapshot directory and file management
//

import Foundation

// MARK: - File Management Protocol

/// Protocol for managing snapshot-related file operations
public protocol GTXSnapshotFileManaging {
    /// Creates a file at the specified path with the given contents
    /// - Parameters:
    ///   - contents: The data to write to the file
    ///   - path: The absolute path where the file should be created
    /// - Throws: An error if the file cannot be created
    func createFile(contents: Data, atPath path: String) throws

    /// Checks if a file exists at the specified path
    /// - Parameter path: The absolute path to check
    /// - Returns: true if a file exists at the path, false otherwise
    func fileExists(atPath path: String) -> Bool

    /// Removes a file at the specified path
    /// - Parameter path: The absolute path of the file to remove
    /// - Throws: An error if the file cannot be removed
    func removeFile(atPath path: String) throws
}

// MARK: - Directory Management Protocol

/// Protocol for managing snapshot-related directory operations
public protocol GTXSnapshotDirectoryManaging {
    /// Creates the accessibility directory structure
    /// - Parameter baseDirectory: The base directory path
    /// - Returns: The path to the created accessibility directory
    /// - Throws: An error if the directory cannot be created
    func createAccessibilityDirectory(baseDirectory: String) throws -> String

    /// Returns the path for a screenshot file
    /// - Parameters:
    ///   - directory: The directory where the screenshot should be saved
    ///   - testName: The name of the test
    /// - Returns: The full path for the screenshot file
    func screenshotPath(in directory: String, testName: String) -> String

    /// Returns the path for an aggregated YAML file
    /// - Parameters:
    ///   - directory: The directory where the YAML should be saved
    ///   - moduleName: The name of the module
    /// - Returns: The full path for the YAML file
    func aggregatedYAMLPath(in directory: String, moduleName: String) -> String
}

// MARK: - Default Implementations

/// Default implementation of GTXSnapshotFileManaging using FileManager
public struct DefaultGTXSnapshotFileManager: GTXSnapshotFileManaging {
    public init() {}

    public func createFile(contents: Data, atPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        try contents.write(to: url)
    }

    public func fileExists(atPath path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    public func removeFile(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}

/// Default implementation of GTXSnapshotDirectoryManaging
public struct DefaultGTXSnapshotDirectoryManager: GTXSnapshotDirectoryManaging {
    public init() {}

    public func createAccessibilityDirectory(baseDirectory: String) throws -> String {
        let accessibilityDir = (baseDirectory as NSString).appendingPathComponent("Accessibility")

        try FileManager.default.createDirectory(
            atPath: accessibilityDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return accessibilityDir
    }

    public func screenshotPath(in directory: String, testName: String) -> String {
        let cleanTestName = testName
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        return (directory as NSString).appendingPathComponent("\(cleanTestName)_screenshot.png")
    }

    public func aggregatedYAMLPath(in directory: String, moduleName: String) -> String {
        let cleanModuleName = moduleName
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        return (directory as NSString).appendingPathComponent("\(cleanModuleName)_gtx_accessibility.yml")
    }
}