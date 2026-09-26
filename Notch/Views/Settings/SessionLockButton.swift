import SwiftUI

/// The header's trailing pill: shows whether the Settings session is
/// unlocked, and doubles as its on/off switch — unlocks while locked, locks
/// while unlocked.
///
/// Ported from Glance (`Settings/SessionLockButton.swift`, MIT © Jonathan
/// Zhou), with `POCController` replaced by this app's
/// `FaceIDCredentialController` — the same session state behind the same
/// Touch ID prompt.
struct SessionLockButton: View {
    @Bindable var credentials: FaceIDCredentialController

    @State private var isUnlocking = false

    var body: some View {
        Button(action: toggleSession) {
            HStack(spacing: 7) {
                Image(systemName: credentials.isSessionUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12))
                    // `.replace` animates the padlock shackle popping open
                    // where supported; SwiftUI falls back to a crossfade.
                    .contentTransition(.symbolEffect(.replace))

                Text(label)
                    .font(SettingsMetrics.headerButtonFont)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(SettingsMetrics.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: SettingsMetrics.headerButtonHeight)
            .background(Capsule().fill(SettingsMetrics.rowColor))
            .overlay(
                Capsule()
                    .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Only disabled mid-authentication — a tap then would double up the
        // Touch ID prompt or race the unresolved lock.
        .disabled(isUnlocking)
        .animation(SettingsMetrics.stateTransitionAnimation, value: credentials.isSessionUnlocked)
        .animation(SettingsMetrics.stateTransitionAnimation, value: isUnlocking)
        .onAppear { credentials.refreshCredentialStatus() }
        // Some unlock paths go through the Face ID controller rather than
        // this button, so this doesn't update reactively on its own — refresh
        // after the notch closes, same as every gated page.
        .onChange(of: FaceIDOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            credentials.refreshCredentialStatus()
        }
    }

    private var label: String {
        if credentials.isSessionUnlocked { return "Session unlocked" }
        return isUnlocking ? "Authenticating…" : "Session locked"
    }

    private func toggleSession() {
        if credentials.isSessionUnlocked {
            credentials.lockSession()
            return
        }
        isUnlocking = true
        Task {
            await credentials.unlockSession()
            isUnlocking = false
        }
    }
}
