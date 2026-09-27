import Foundation

/// Only the release bundle identifier maps to the original "FujiRecipes"
/// folder, so Debug, test, and unbundled runs never read or rewrite a release
/// install's recipes or crash reports.
public enum AppSupportDirectory {
    public static let releaseBundleIdentifier = "com.ant.fuji-recipes-mac"

    public static var current: URL {
        url(forBundleIdentifier: Bundle.main.bundleIdentifier)
    }

    public static func url(forBundleIdentifier bundleIdentifier: String?) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = bundleIdentifier == releaseBundleIdentifier
            ? "FujiRecipes"
            : "FujiRecipes-\(bundleIdentifier ?? "unbundled")"
        return root.appendingPathComponent(folder, isDirectory: true)
    }
}
