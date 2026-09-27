import SwiftUI
import FujiRecipesCore

private struct ClearLocalDraftConfirmation: ViewModifier {
    @Binding var slot: Int?
    let loadouts: LoadoutStore

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Clear Local Draft?",
                isPresented: Binding(
                    get: { slot != nil },
                    set: { if !$0 { slot = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Clear Local Draft", role: .destructive) {
                    if let slot {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            loadouts.clearLoadout(for: slot)
                        }
                    }
                    slot = nil
                }
                Button("Cancel", role: .cancel) { slot = nil }
            } message: {
                if let slot {
                    Text("This removes only FujiRecipes’ local draft for C\(slot). It does not clear, reset, or otherwise change the physical camera slot.")
                }
            }
    }
}

extension View {
    func clearLocalDraftConfirmation(slot: Binding<Int?>, loadouts: LoadoutStore) -> some View {
        modifier(ClearLocalDraftConfirmation(slot: slot, loadouts: loadouts))
    }
}
