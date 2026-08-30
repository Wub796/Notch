import AppKit
import SwiftUI

/// The shelf tab: a horizontal tray of dropped files with drag-out support,
/// per-item actions, and bulk AirDrop / clear.
struct ShelfView: View {
    let shelf: ShelfController
    let state: NotchState

    init(state: NotchState) {
        self.state = state
        shelf = state.shelf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Shelf", subtitle: subtitle) {
                if !shelf.items.isEmpty {
                    HStack(spacing: NotchTheme.Space.s) {
                        ScreenTextButton(
                            title: "AirDrop All",
                            systemImage: "airplane.circle.fill",
                            isProminent: true
                        ) {
                            shelf.airDropAll()
                            state.showToast(
                                "AirDropping \(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")",
                                symbol: "airplane"
                            )
                        }

                        ScreenTextButton(title: "Clear", systemImage: "xmark.circle") {
                            withAnimation(.notchSpring) { shelf.clear() }
                            state.showToast("Shelf cleared", symbol: "xmark.circle")
                        }
                    }
                }
            }

            if shelf.items.isEmpty {
                ScreenEmptyState(
                    symbol: "tray",
                    title: "Nothing on the shelf",
                    caption: "Drag files onto the notch to park them here"
                )
                .notchCard()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NotchTheme.Space.m) {
                        ForEach(shelf.items) { item in
                            ShelfItemCard(item: item, shelf: shelf, state: state)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .notchScrollFadeHorizontal(10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.notchSpring, value: shelf.items)
    }

    private var subtitle: String {
        let count = shelf.items.count
        guard count > 0 else { return "Drop files to keep them close" }
        return "\(count) item\(count == 1 ? "" : "s") · drag one out to move it"
    }
}

private struct ShelfItemCard: View {
    let item: ShelfController.Item
    let shelf: ShelfController
    let state: NotchState

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
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
        .frame(width: 112)
        .background {
            RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
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
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
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
        .help("\(item.name) — double-click to open")
    }
}
