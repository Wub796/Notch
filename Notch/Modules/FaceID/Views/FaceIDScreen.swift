import AVFoundation
import AppKit
import SwiftUI

/// The Face ID screen in the notch panel: where a face is enrolled, where the
/// password is stored, and where a scan can be tried before trusting it.
///
/// The screen is deliberately explicit about what this feature is and is not.
/// It types the Mac's password for you at the lock screen, so the caveat about
/// what a webcam can and cannot prove is on the screen that turns it on rather
/// than buried in a settings pane two clicks away.
struct FaceIDScreen: View {
    let state: NotchState

    @State private var enrollmentName = ""
    @State private var isEnrolling = false
    @State private var enrollmentError: String?

    private var faceID: FaceIDController { state.faceID }
    private var settings: FaceIDSettings { .shared }
    private var enrollment: FaceIDEnrollmentSession { state.faceIDEnrollment }
    private var credentials: FaceIDCredentialController { faceID.credentials }
    private var store: FaceEnrollmentStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Face ID", subtitle: subtitle) {
                HStack(spacing: NotchTheme.Space.s) {
                    if faceID.isScanning {
                        ScreenTextButton(title: "Stop", systemImage: "stop.fill", tint: .orange) {
                            faceID.endManualScan()
                        }
                    } else if settings.isEnabled {
                        ScreenTextButton(title: "Test scan", systemImage: "faceid") {
                            faceID.startManualScan()
                        }
                        .disabled(store.activeIdentities.isEmpty || !credentials.hasStoredPassword)
                    }
                }
            }

            // Scrolling, deliberately, and this tab's height stays fixed (see
            // `NotchSizing.baseSize`) so the slab cannot jump while enrollment
            // changes the left column's height. The two together are the point:
            // the fixed budget is smaller than these columns need — a preview
            // card, the Touch ID/password/accessibility rows, the face list and
            // the last-scan readout — and without a scroll view the bottom of
            // them simply sat below the panel, with no way to reach it. The
            // screen read as inert, which is exactly what an unreachable Touch
            // ID button looks like. The header stays outside, so "Test scan" is
            // there whatever the content is doing.
            ScrollView(.vertical, showsIndicators: false) {
                if !settings.isEnabled {
                    introduction
                } else {
                    HStack(alignment: .top, spacing: NotchTheme.Space.m) {
                        leftColumn
                        rightColumn
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .notchScrollFade()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            credentials.refreshAccessibilityStatus()
            credentials.refreshCredentialStatus()
            store.reloadIfUnlocked()
        }
    }

    private var subtitle: String {
        guard settings.isEnabled else { return "Off" }
        if faceID.isScanning { return faceID.statusMessage }
        if let outcome = faceID.lastOutcome { return outcome }
        return faceID.statusMessage
    }

    // MARK: - Introduction (feature off)

    /// The one-time gate. Two things are stated plainly here because they are the
    /// terms the feature is offered on: a webcam cannot prove identity the way a
    /// depth-sensing camera can, and macOS offers no supported way to log in, so
    /// the password is typed by synthesizing keystrokes.
    private var introduction: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            Text("Face ID unlocks this Mac by recognizing your face at the lock screen — and typing your password for you when it does.")
                .font(.notchCallout)
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
                caveatRow(
                    "person.crop.circle.badge.xmark",
                    "A webcam sees a flat picture, with none of the depth sensing an iPhone uses. "
                        + "A printed photo and a photo on a screen are rejected; a video replay is not reliably rejected."
                )
                caveatRow(
                    "keyboard",
                    "macOS has no API for authorizing a login, so the password is typed into the lock screen's own field. "
                        + "It is stored encrypted behind Touch ID and only read while the screen is actually locked."
                )
                caveatRow(
                    "lock.shield",
                    "It is a convenience, not a security upgrade. Leave it off if someone else can get to your Mac with a picture of you."
                )
            }

            ScreenTextButton(title: "I understand — turn on Face ID", systemImage: "faceid", isProminent: true) {
                settings.hasAcknowledgedSetup = true
                settings.isEnabled = true
                withAnimation(NotchAnimations.content) {}
                state.showToast("Face ID is on — enroll a face next", symbol: "faceid")
            }
        }
        .padding(NotchTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    private func caveatRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: NotchTheme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(width: 16)
            Text(text)
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Left column: preview, enrollment, setup

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            previewSection
            setupSection
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var previewSection: some View {
        if isEnrolling {
            enrollmentSection
        } else {
            idlePreview
        }
    }

    /// What the screen shows when nothing is being captured: the faces enrolled and
    /// where the last scan landed, rather than an empty black rectangle.
    private var idlePreview: some View {
        HStack(alignment: .top, spacing: NotchTheme.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                Image(systemName: store.activeIdentities.isEmpty ? "person.crop.circle.badge.plus" : "faceid")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
                Text(store.activeIdentities.isEmpty ? "No face enrolled yet" : "\(store.activeIdentities.count) face\(store.activeIdentities.count == 1 ? "" : "s") enrolled")
                    .font(.notchHeadline)
                    .foregroundStyle(NotchTheme.inkPrimary)

                Text("Enrolling walks you through nine head positions. Each one is turned into a 512-number fingerprint and the image is discarded — nothing is written to disk but those numbers, encrypted.")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if store.isLocked {
                    lockedNotice
                } else {
                    enrolledSummary
                }

                HStack(spacing: NotchTheme.Space.s) {
                    ScreenTextButton(
                        title: store.identities.isEmpty ? "Enroll a face" : "Enroll another",
                        systemImage: "faceid",
                        isProminent: true
                    ) {
                        // A locked session used to disable this button — and with
                        // "Test scan" disabled for the same reason, a screen with
                        // nothing to click reads as a feature that does nothing.
                        // Unlocking is what the click is actually asking for, so it
                        // asks for it and then carries on into the capture.
                        guard credentials.isSessionUnlocked else {
                            Task {
                                await credentials.unlockSession()
                                guard credentials.isSessionUnlocked else {
                                    // Returning silently here is what made this
                                    // button read as broken: the unlock can fail
                                    // with nothing on screen unless its reason is
                                    // echoed back next to the click.
                                    enrollmentError = credentials.sessionError
                                        ?? "Touch ID didn't unlock the session, so the capture can't start."
                                    return
                                }
                                // The store reloads on the session's own notification,
                                // and that is not ordered against this task: reading it
                                // here is what keeps nine poses from ending in a save
                                // that fails because the store had not loaded yet.
                                store.reloadIfUnlocked()
                                beginEnrollment()
                            }
                            return
                        }
                        store.reloadIfUnlocked()
                        beginEnrollment()
                    }
                    // Disabled for a store that was read and would not open (the
                    // right column says why), and while a Touch ID prompt is
                    // outstanding so a second click can't stack another one.
                    .disabled(store.loadFailure != nil || credentials.isAuthenticating)
                }
                .padding(.top, 2)

                if let enrollmentError {
                    Text(enrollmentError)
                        .font(.notchFootnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(NotchTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    /// The identity list, collapsed to a summary line — the full list lives in the
    /// right column, and the same rows twice would be noise.
    private var enrolledSummary: some View {
        let poorSamples = store.identities.flatMap(\.samples).filter { $0.qualityTier == .poor }.count
        return HStack(spacing: NotchTheme.Space.s) {
            Label("\(store.identities.reduce(0) { $0 + $1.samples.count }) samples", systemImage: "square.stack.3d.up")
            if poorSamples > 0 {
                Label("\(poorSamples) soft", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.notchFootnote)
        .foregroundStyle(NotchTheme.inkMuted)
    }

    private var lockedNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Locked — authenticate with Touch ID to see or add faces.")
                .font(.notchFootnote)
        }
        .foregroundStyle(.orange)
    }

    // MARK: - Enrollment

    /// The guided capture: a live preview with the detected face boxed, the current
    /// instruction, and a progress ring — plus the sweep ribbons, which are the cue
    /// for which way to turn when the instruction alone isn't enough.
    private var enrollmentSection: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            ZStack {
                if case .capturing = enrollment.phase, let session = activeSession {
                    FaceIDCameraPreview(session: session, faces: enrollment.previewFaces)
                        .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                }

                if case .capturing = enrollment.phase,
                   let travel = FaceIDEnrollmentSweepView.travel(for: enrollment.currentPose) {
                    FaceIDEnrollmentSweepView(travel: travel)
                        .id(enrollment.currentPose)
                        .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: NotchTheme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instructionTitle)
                        .font(.notchHeadline)
                        .foregroundStyle(NotchTheme.inkPrimary)
                    Text(enrollment.hint)
                        .font(.notchFootnote)
                        .foregroundStyle(enrollment.isTooFar ? .orange : NotchTheme.inkMuted)
                }

                Spacer(minLength: NotchTheme.Space.s)

                poseProgressRing
            }

            if case .ready = enrollment.phase {
                saveRow
            } else if case .failed(let message) = enrollment.phase {
                Text(message)
                    .font(.notchFootnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: NotchTheme.Space.s) {
                if case .ready = enrollment.phase {
                    ScreenTextButton(title: "Discard", systemImage: "trash", tint: .orange) {
                        cancelEnrollment()
                    }
                } else {
                    ScreenTextButton(title: "Cancel", systemImage: "xmark") {
                        cancelEnrollment()
                    }
                }
            }
        }
        .padding(NotchTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    private var instructionTitle: String {
        switch enrollment.phase {
        case .starting: "Starting the camera…"
        case .capturing: enrollment.currentPose.instruction
        case .ready: "All nine positions captured"
        case .failed: "Enrollment stopped"
        case .idle: "Ready"
        }
    }

    private var poseProgressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, enrollment.poseProgress))
                .stroke(FaceIDAccent.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(min(enrollment.captureCount, FaceIDEnrollmentSession.totalSampleCount))/\(FaceIDEnrollmentSession.totalSampleCount)")
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkSecondary)
        }
        .frame(width: 34, height: 34)
    }

    private var saveRow: some View {
        HStack(spacing: NotchTheme.Space.s) {
            TextField("Name this face", text: $enrollmentName)
                .textFieldStyle(.plain)
                .font(.notchCallout)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
                .frame(maxWidth: 180)

            ScreenTextButton(title: "Save face", systemImage: "checkmark", isProminent: true) {
                saveEnrollment()
            }
            .disabled(enrollmentName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func beginEnrollment() {
        enrollmentError = nil
        enrollmentName = ""
        isEnrolling = true
        enrollment.start()
    }

    private func cancelEnrollment() {
        enrollment.cancel()
        isEnrolling = false
    }

    private func saveEnrollment() {
        do {
            let name = enrollmentName
            try enrollment.commit(name: name, replacing: nil)
            isEnrolling = false
            enrollmentName = ""
            state.showToast("Enrolled \(name)", symbol: "faceid")
        } catch {
            enrollmentError = error.localizedDescription
        }
    }

    private var activeSession: AVCaptureSession? {
        faceID.camera.session
    }

    /// Set only when a display was pinned and is not attached: the state in which
    /// Face ID is configured, armed and unable to appear anywhere at all.
    private var missingDisplayWarning: String? {
        guard settings.preferredDisplayID != nil else { return nil }
        guard FaceIDGeometry.preferredScreen() == nil else { return nil }
        return FaceIDGeometry.pinnedDisplayMissingMessage
    }

    // MARK: - Setup (Touch ID session, password, Accessibility)

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            row(
                symbol: credentials.isSessionUnlocked ? "lock.open.fill" : "lock.fill",
                title: "Touch ID session",
                // Waiting is stated rather than implied: the prompt is a system
                // window that can open behind the panel, and a click that shows
                // nothing at all is indistinguishable from a broken button.
                detail: credentials.isAuthenticating
                    ? "Waiting for Touch ID — the prompt is a system window, so check behind other windows."
                    : (credentials.isSessionUnlocked
                        ? "Unlocked. It re-locks after \(settings.autoLockInterval.title) of inactivity."
                        : "Locked. Touch ID is asked once, not on every unlock — nothing can answer a prompt at the lock screen."),
                tint: credentials.isSessionUnlocked ? NotchTheme.battery : .orange
            ) {
                ScreenTextButton(
                    title: credentials.isSessionUnlocked
                        ? "Lock"
                        : (credentials.isAuthenticating ? "Waiting…" : "Unlock"),
                    systemImage: credentials.isSessionUnlocked ? "lock.fill" : "touchid"
                ) {
                    if credentials.isSessionUnlocked {
                        credentials.lockSession()
                    } else {
                        Task { await credentials.unlockSession() }
                    }
                }
                .disabled(credentials.isAuthenticating)
            }

            if let error = credentials.sessionError {
                VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
                    Text(error)
                        .font(.notchFootnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    // The one failure retrying cannot clear, so the way out is
                    // offered here instead of being described: unlocking can
                    // never succeed while the old key is missing, which would
                    // otherwise leave these buttons permanently inert.
                    if credentials.needsResetBeforeUse {
                        ScreenTextButton(title: "Reset Face ID data", systemImage: "trash", tint: .orange) {
                            credentials.deleteEverything()
                            enrollmentError = nil
                            store.reloadIfUnlocked()
                        }
                    }
                }
            }

            // The one blocker that leaves no other trace: nothing happens at the
            // lock screen, and nothing here says why. `evaluateTrigger` sets the
            // same sentence as its status message, so a scan that goes nowhere
            // and a look at this screen agree about the reason.
            if let warning = missingDisplayWarning {
                row(
                    symbol: "display",
                    title: "Display",
                    detail: warning,
                    tint: .orange
                ) {
                    EmptyView()
                }
            }

            row(
                symbol: credentials.hasStoredPassword ? "key.fill" : "key",
                title: "Stored password",
                detail: credentials.hasStoredPassword
                    ? "Encrypted with a key held in the keychain behind Touch ID. Choosing Remove clears the password and every enrolled face."
                    : "Your Mac's login password. It is only read when a scan succeeds on a screen CGSession confirms is locked.",
                tint: credentials.hasStoredPassword ? NotchTheme.battery : NotchTheme.inkMuted
            ) {
                if credentials.hasStoredPassword {
                    ScreenTextButton(title: "Remove", systemImage: "trash", tint: .orange) {
                        credentials.deleteEverything()
                        state.showToast("Face ID data removed", symbol: "trash")
                    }
                }
            }

            if !credentials.hasStoredPassword {
                HStack(spacing: NotchTheme.Space.s) {
                    SecureField("Mac login password", text: Bindable(credentials).passwordInput)
                        .textFieldStyle(.plain)
                        .font(.notchCallout)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }
                        .disabled(!credentials.isSessionUnlocked)
                        .frame(maxWidth: 220)

                    ScreenTextButton(title: "Save", systemImage: "checkmark", isProminent: true) {
                        Task { await credentials.savePassword() }
                    }
                    .disabled(!credentials.isSessionUnlocked || credentials.passwordInput.isEmpty)
                }
            }

            row(
                symbol: credentials.accessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill",
                title: "Accessibility",
                detail: credentials.accessibilityGranted
                    ? "Granted — Notch can type the password into the lock screen."
                    : "Needed to type the password. Without it a scan still runs and still reports, it just can't unlock anything.",
                tint: credentials.accessibilityGranted ? NotchTheme.battery : .orange
            ) {
                if !credentials.accessibilityGranted {
                    ScreenTextButton(title: "Grant", systemImage: "hand.raised") {
                        credentials.requestAccessibility()
                    }
                }
            }

            if let fallback = faceID.pipeline.fallbackReason {
                Text("Recognition is running on Apple's feature print rather than ArcFace, so faces can't be told apart reliably: \(fallback)")
                    .font(.notchFootnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NotchTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    private func row<Trailing: View>(
        symbol: String,
        title: String,
        detail: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: NotchTheme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.notchCallout.weight(.semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(detail)
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: NotchTheme.Space.s)

            trailing()
        }
    }

    // MARK: - Right column: faces and diagnostics

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            identitiesSection
            diagnosticsSection
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var identitiesSection: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
            Text("YOUR FACES")
                .font(.notchEyebrow)
                .tracking(0.8)
                .foregroundStyle(NotchTheme.inkMuted)

            if store.isLocked {
                Text("Unlock the Touch ID session to load them.")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
            } else if let failure = store.loadFailure {
                Text(failure)
                    .font(.notchFootnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.identities.isEmpty {
                Text("Nothing enrolled.")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: NotchTheme.Space.xs) {
                        ForEach(Array(store.identities.enumerated()), id: \.element.id) { index, identity in
                            identityRow(identity)
                                .notchRowEntrance(index)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .notchScrollFade()
            }
        }
        .padding(NotchTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    private func identityRow(_ identity: FaceIdentity) -> some View {
        HStack(spacing: NotchTheme.Space.s) {
            Image(systemName: identity.isEnabled ? "face.smiling.fill" : "face.smiling")
                .font(.system(size: 14))
                .foregroundStyle(identity.isEnabled ? FaceIDAccent.accent : NotchTheme.inkMuted)

            VStack(alignment: .leading, spacing: 1) {
                Text(identity.name)
                    .font(.notchCallout.weight(.semibold))
                    .foregroundStyle(identity.isEnabled ? NotchTheme.inkPrimary : NotchTheme.inkMuted)
                HStack(spacing: 5) {
                    Text("\(identity.samples.count) samples")
                    qualityTicks(for: identity)
                    if identity.isStale(comparedTo: faceID.pipeline.embedder) {
                        Text("· stale model")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
            }

            Spacer(minLength: NotchTheme.Space.xs)

            NotchIconButton(
                systemImage: identity.isEnabled ? "checkmark.circle.fill" : "circle",
                isActive: identity.isEnabled,
                help: identity.isEnabled ? "Stop this face unlocking" : "Let this face unlock",
                activeTint: NotchTheme.battery
            ) {
                try? store.setEnabled(!identity.isEnabled, for: identity.id)
            }

            NotchIconButton(
                systemImage: "trash",
                help: "Delete \(identity.name)",
                activeTint: .orange
            ) {
                try? store.delete(identity)
                state.showToast("Deleted \(identity.name)", symbol: "trash")
            }
        }
        .padding(.horizontal, NotchTheme.Space.s)
        .padding(.vertical, 5)
        .notchTile()
    }

    /// One tick per sample, coloured by Vision's capture-quality score — the only
    /// way a user can tell a careful enrollment from a rushed one after the fact.
    private func qualityTicks(for identity: FaceIdentity) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(identity.samples.enumerated()), id: \.offset) { _, sample in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(qualityColor(sample.qualityTier))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private func qualityColor(_ tier: FaceSample.QualityTier) -> Color {
        switch tier {
        case .unrated: Color.white.opacity(0.25)
        case .poor: .orange
        case .fair: .yellow.opacity(0.8)
        case .good: NotchTheme.battery
        }
    }

    /// The numbers behind the last scan. Deliberately shown rather than hidden: a
    /// threshold nobody can see the effect of is a threshold nobody can tune, and
    /// the failure mode of a too-strict one is "it just never works".
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
            Text("LAST SCAN")
                .font(.notchEyebrow)
                .tracking(0.8)
                .foregroundStyle(NotchTheme.inkMuted)

            diagnosticsGrid

            if settings.livenessChecksEnabled {
                livenessGrid
            }
        }
        .padding(NotchTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    private var diagnosticsGrid: some View {
        VStack(alignment: .leading, spacing: 3) {
            diagnosticLine("Embedder", faceID.pipeline.embedder.name)
            diagnosticLine("Threshold", String(format: "%.2f", settings.matchThreshold))
            diagnosticLine("Match", matchSummary)
            diagnosticLine("Alignment", faceID.lastAlignmentTier?.rawValue ?? "—")
            diagnosticLine("Quality", faceID.lastQuality.map { String(format: "%.2f", $0) } ?? "—")
        }
    }

    private var matchSummary: String {
        guard let best = faceID.lastScored.first else { return "no face in frame" }
        let verdict = best.identity.isStale(comparedTo: faceID.pipeline.embedder) ? "stale" : "template"
        return String(format: "%@ %.3f (%@)", best.identity.name, best.centroidSimilarity, verdict)
    }

    private func diagnosticLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: NotchTheme.Space.s) {
            Text(label)
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.notchFootnote.weight(.semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var livenessGrid: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(LivenessCue.allCases) { cue in
                let state = faceID.lastLiveness.state(for: cue)
                HStack(spacing: 6) {
                    Circle()
                        .fill(cue.role == .deny
                              ? (state.hasFired ? Color.red : Color.white.opacity(0.18))
                              : (state.hasFired ? NotchTheme.battery : Color.white.opacity(0.18)))
                        .frame(width: 5, height: 5)
                    Text(cue.title)
                        .font(.notchFootnote)
                        .foregroundStyle(NotchTheme.inkMuted)
                        .frame(width: 96, alignment: .leading)
                    Text(state.hasFired ? "fired" : String(format: "%.2f", state.reading.level))
                        .font(.notchFootnote)
                        .foregroundStyle(NotchTheme.inkMuted)
                    Spacer(minLength: 0)
                }
                .help(cue.explanation)
            }
        }
        .padding(.top, 2)
    }
}
