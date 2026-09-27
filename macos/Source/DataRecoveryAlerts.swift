import SwiftUI
import AppKit
import FujiRecipesCore

private struct DataRecoveryAlerts: ViewModifier {
    @ObservedObject var library: CustomRecipeLibrary

    func body(content: Content) -> some View {
        content
            .alert(
                "My Recipes Didn’t Load Cleanly",
                isPresented: Binding(
                    get: { library.loadIssue != nil },
                    set: { if !$0 { library.acknowledgeLoadIssue() } }
                ),
                presenting: library.loadIssue
            ) { issue in
                if let backupURL = issue.backupURL {
                    Button("Show Copy in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                        library.acknowledgeLoadIssue()
                    }
                }
                Button("OK") { library.acknowledgeLoadIssue() }
                    .keyboardShortcut(.defaultAction)
            } message: { issue in
                Text(issue.message)
            }
    }
}

extension View {
    func dataRecoveryAlerts(library: CustomRecipeLibrary) -> some View {
        modifier(DataRecoveryAlerts(library: library))
    }
}
