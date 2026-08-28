import AppKit
import SwiftUI

/// The shelf tab: a horizontal tray of dropped files with drag-out support,
/// per-item actions, and bulk AirDrop / clear.
struct ShelfView: View {
    let shelf: ShelfController

    var body: some View {
        if shelf.items.isEmpty {
            emptyState
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfItemCard(item: item, shelf: shelf)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.notchSpring, value: shelf.items)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(NotchTheme.inkMuted)
            Text("Shelf is empty")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
            Text("Drop files onto the notch to keep them here,\nthen drag them out or AirDrop them")
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button {
                shelf.airDropAll()
            } label: {
                Label("AirDrop All", systemImage: "airplane.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.blue))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableButtonStyle())
            .hoverLift(1.04)

            Spacer()

            Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(NotchTheme.inkMuted)

            Button {
                withAnimation(.notchSpring) {
                    shelf.clear()
                }
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NotchTheme.surface))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            .buttonStyle(PressableButtonStyle())
            .hoverLift(1.04)
        }
    }
}

private struct ShelfItemCard: View {
    let item: ShelfController.Item
    let shelf: ShelfController

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(item.detail)
                .font(.system(size: 8.5))
                .foregroundStyle(NotchTheme.inkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: 92)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? NotchTheme.surfaceHover : NotchTheme.surface)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    withAnimation(.notchSpring) {
                        shelf.remove(item)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.opacity)
            }
        }
        .onHover { isHovering in
            withAnimation(.notchSpring) {
                hovering = isHovering
            }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("AirDrop") { shelf.airDrop(item) }
            Button("Copy") { shelf.copyToPasteboard(item) }
            Button("Reveal in Finder") { shelf.revealInFinder(item) }
            Divider()
            Button("Remove from Shelf") {
                withAnimation(.notchSpring) {
                    shelf.remove(item)
                }
            }
        }
        .help(item.name)
    }
}
