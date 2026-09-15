import AppKit
import SwiftUI

/// The shelf: an AirDrop target and a drop area, side by side.
///
/// After the reference: two dashed wells rather than a titled screen. Dropping
/// on the left sends straight to AirDrop; dropping on the right parks the files
/// here, as a row you can drag back out. The dashes are the affordance — this
/// is the one screen that exists to be dropped on, so it is drawn the way drop
/// targets are drawn.
struct ShelfView: View {
    let state: NotchState

    private var shelf: ShelfController { state.shelf }

    @State private var airDropTargeted = false
    @State private var shelfTargeted = false

    /// The wells' height, which is also what the slab fits itself to.
    static let wellHeight: CGFloat = 150
    private static let airDropWidth: CGFloat = 150

    var body: some View {
        HStack(spacing: NotchTheme.Space.m) {
            airDropWell
                .frame(width: Self.airDropWidth)
            shelfWell
                .frame(maxWidth: .infinity)
        }
        .frame(height: Self.wellHeight)
        .animation(NotchAnimations.content, value: shelf.items)
        .animation(NotchAnimations.content, value: airDropTargeted)
        .animation(NotchAnimations.content, value: shelfTargeted)
    }

    // MARK: - AirDrop

    private var airDropWell: some View {
        Button(action: sendShelfToAirDrop) {
            VStack(spacing: NotchTheme.Space.s) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(airDropTargeted ? 0.18 : 0.1))
                    AirDropIcon()
                        .frame(width: 40, height: 40)
                }
                .frame(width: 66, height: 66)
                .scaleEffect(airDropTargeted ? 1.08 : 1)

                VStack(spacing: 2) {
                    Text("AirDrop")
                        .font(.notchBody.weight(.bold))
                        .foregroundStyle(NotchTheme.inkPrimary)
                    Text(airDropCaption)
                        .font(.notchFootnote)
                        .foregroundStyle(NotchTheme.inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .background { DashedWell(isTargeted: airDropTargeted) }
        .overlay(alignment: .topTrailing) {
            instantAirDropToggle
                .padding(8)
        }
        .onDrop(of: ShelfController.acceptedTypes, isTargeted: $airDropTargeted) { providers in
            shelf.handleDrop(providers, destination: .airDrop) { accepted in
                guard accepted > 0 else { return }
                state.showToast(
                    "Sending \(accepted) item\(accepted == 1 ? "" : "s") with AirDrop",
                    symbol: "airplane"
                )
            }
            return true
        }
        .help(shelf.items.isEmpty
            ? "Drop files here to AirDrop them"
            : "AirDrop everything on the shelf")
    }

    private var airDropCaption: String {
        let count = shelf.items.count
        guard count > 0 else { return "Drop to send" }
        return "Send \(count) item\(count == 1 ? "" : "s")"
    }

    private func sendShelfToAirDrop() {
        let count = shelf.items.count
        guard count > 0 else {
            state.showToast("Drop files on AirDrop to send them", symbol: "airplane")
            return
        }
        shelf.airDropAll()
        state.showToast("AirDropping \(count) item\(count == 1 ? "" : "s")", symbol: "airplane")
    }

    /// The reference's corner switch: whether anything dropped on the notch —
    /// not just on this well — goes straight to AirDrop.
    private var instantAirDropToggle: some View {
        let isOn = state.settings.instantAirDrop
        return Button {
            state.settings.instantAirDrop.toggle()
            state.showToast(
                isOn ? "Drops go to the shelf" : "Drops go straight to AirDrop",
                symbol: isOn ? "tray" : "airplane"
            )
        } label: {
            Image(systemName: "switch.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.blue : NotchTheme.inkMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(isOn
            ? "Anything dropped on the notch goes to AirDrop. Click to shelve drops instead."
            : "Send anything dropped on the notch straight to AirDrop")
        .accessibilityLabel("Instant AirDrop")
        .accessibilityValue(isOn ? "on" : "off")
    }

    // MARK: - Shelf

    private var shelfWell: some View {
        ZStack {
            if shelf.items.isEmpty {
                VStack(spacing: NotchTheme.Space.s) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(shelfTargeted ? .fill : .none)
                        .font(.system(size: 24))
                        .foregroundStyle(shelfTargeted ? Color.blue : NotchTheme.inkSecondary)
                    Text(shelfTargeted ? "Release to add" : "Drop files here")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                }
                .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NotchTheme.Space.s) {
                        ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                            ShelfItemCard(item: item, shelf: shelf, state: state)
                                .notchRowEntrance(index)
                        }
                    }
                    .padding(.horizontal, NotchTheme.Space.m)
                }
                .notchScrollFadeHorizontal(12)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { DashedWell(isTargeted: shelfTargeted) }
        .overlay(alignment: .topTrailing) {
            if !shelf.items.isEmpty {
                Button {
                    withAnimation(NotchAnimations.content) { shelf.clear() }
                    state.showToast("Shelf cleared", symbol: "xmark.circle")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(NotchTheme.inkMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(8)
                .help("Clear the shelf")
                .accessibilityLabel("Clear the shelf")
            }
        }
        .onDrop(of: ShelfController.acceptedTypes, isTargeted: $shelfTargeted) { providers in
            shelf.handleDrop(providers, destination: .shelf) { _ in }
            return true
        }
    }
}

/// A drop target's well: a dashed rounded outline that brightens and takes a
/// blue tint while something is held over it.
private struct DashedWell: View {
    let isTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            shape.fill(isTargeted ? Color.blue.opacity(0.12) : Color.white.opacity(0.02))
            shape.strokeBorder(
                isTargeted ? Color.blue.opacity(0.85) : Color.white.opacity(0.26),
                style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
            )
        }
    }
}

/// The system's own AirDrop icon, with a symbol where the Finder's AirDrop app
/// is not at its usual path.
private struct AirDropIcon: View {
    private static let image: NSImage? = {
        let path = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
        }
    }
}

private struct ShelfItemCard: View {
    let item: ShelfController.Item
    let shelf: ShelfController
    let state: NotchState

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.thumb, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            Text(item.name)
                .font(.notchCaption)
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(item.detail)
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, NotchTheme.Space.s)
        .padding(.vertical, 12)
        .frame(width: 108)
        .background {
            RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    withAnimation(.notchSpring) {
                        shelf.remove(item)
                    }
                    state.showToast("Removed from shelf", symbol: "trash")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.opacity)
                .accessibilityLabel("Remove \(item.name) from shelf")
            }
        }
        .onHover { isHovering in
            withAnimation(.notchSpring) {
                hovering = isHovering
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .onDrag {
            // The provider is handed to the destination; the shelf only needs
            // to know the drag started so it can clear the item afterwards
            // when the user has asked it to.
            defer { shelf.handleDragOut(item) }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("AirDrop") {
                shelf.airDrop(item)
                state.showToast("AirDrop sent", symbol: "airplane")
            }
            Button("Copy") {
                shelf.copyToPasteboard(item)
                state.showToast("Copied", symbol: "doc.on.doc")
            }
            Button("Reveal in Finder") { shelf.revealInFinder(item) }
            Divider()
            Button("Remove from Shelf") {
                withAnimation(.notchSpring) {
                    shelf.remove(item)
                }
                state.showToast("Removed from shelf", symbol: "trash")
            }
        }
        .help("\(item.name). Double-click to open")
    }
}
