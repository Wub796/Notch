import SwiftUI
import UniformTypeIdentifiers

/// Drop target for the whole notch surface. Dragging anything over the
/// collapsed notch springs it open into the drop zone; releasing shelves the
/// items (or AirDrops immediately, per settings).
struct NotchDropDelegate: DropDelegate {
    let state: NotchState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: ShelfController.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.notchSpring) {
            state.isDropTargeted = true
        }
        state.expand()
    }

    func dropExited(info: DropInfo) {
        withAnimation(.notchSpring) {
            state.isDropTargeted = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.notchSpring) {
            state.isDropTargeted = false
        }
        let providers = info.itemProviders(for: ShelfController.acceptedTypes)
        guard !providers.isEmpty else { return false }

        state.shelf.handleDrop(providers) { accepted in
            // Land the user on the shelf so they see their items arrive.
            if accepted > 0, !NotchSettings.shared.instantAirDrop {
                state.select(.shelf)
            }
        }
        return true
    }
}
