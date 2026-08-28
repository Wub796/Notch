import SwiftUI
import UniformTypeIdentifiers

/// Drop target for the whole notch surface. Dragging anything over the
/// collapsed notch springs it open into the AirDrop zone; releasing hands the
/// items straight to the AirDrop sharing service.
struct NotchDropDelegate: DropDelegate {
    let state: NotchState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: AirDropController.acceptedTypes)
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
        let providers = info.itemProviders(for: AirDropController.acceptedTypes)
        guard !providers.isEmpty else { return false }
        state.airDrop.share(providers)
        return true
    }
}
