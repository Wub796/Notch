import AppKit
import SwiftUI

/// Face ID's settings page — the content of the app's Face ID tab.
///
/// Built from Glance's settings pages (`Settings/Pages/*.swift`, MIT ©
/// Jonathan Zhou), stacked into one page because this app's window has one
/// tab per feature while Glance's has one per Face ID page. Same rows, same
/// grouping, same order, same wording where it still applies: the enable
/// switch and trigger picker, Behaviour, Animation, then the four areas that
/// need the Touch ID session — Face, Password, Camera, Recognition.
///
/// Where Glance sends the user to its own onboarding window, this page sends
/// them to the notch's Face ID screen (`FaceIDScreen`), which is where this
/// app's enrollment lives.
struct FaceIDSettingsPane: View {
    @Bindable private var settings = FaceIDSettings.shared
    @Bindable private var credentials = FaceIDCredentialController.shared
    @Bindable private var store = FaceEnrollmentStore.shared

    @State private var isUnlocking = false
    @State private var sessionError: String?
    @State private var statusMessage: String?
    /// Surfaced when an encrypted write fails (realistically: the session
    /// lapsed between rendering and tapping). The store rolls back on
    /// failure, so the control snaps back on its own — this explains why.
    @State private var writeError: String?
    @State private var identityPendingDeletion: FaceIdentity?
    /// Refreshed on `didChangeScreenParametersNotification` so the picker
    /// reflects displays connecting/disconnecting while Settings is open.
    @State private var screens: [NSScreen] = NSScreen.screens
    @State private var cameras: [FaceIDCameraDevice] = FaceIDCameraCatalog.availableDevices()
    @State private var previewCamera = FaceIDCamera()
    @State private var isPreviewShown = false

    private var isSessionUnlocked: Bool { credentials.isSessionUnlocked }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            generalGroup
            if needsAccessibility { accessibilityNotice }
            behaviourSection
            animationSection

            if credentials.hasStoredPassword {
                if isSessionUnlocked {
                    faceSection
                    passwordUnlockedSection
                } else {
                    lockedState
                }
            } else {
                passwordSetupSection
            }

            if isSessionUnlocked {
                cameraSection
                recognitionSection
            }

            if let statusMessage {
                SettingsCaption(text: statusMessage)
            }
        }
        .animation(SettingsMetrics.stateTransitionAnimation, value: isSessionUnlocked)
        .animation(SettingsMetrics.stateTransitionAnimation, value: credentials.hasStoredPassword)
        // Published for the window's header, which draws the refresh control
        // rather than the page keeping a button of its own — see
        // `HeaderTrailingActionKey`.
        .preference(
            key: HeaderTrailingActionKey.self,
            value: isSessionUnlocked ? HeaderAction(perform: refreshCameras) : nil
        )
        .onAppear {
            credentials.refreshCredentialStatus()
            store.reloadIfUnlocked()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
        // Granting Accessibility in System Settings clears the notice below
        // without a relaunch.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            credentials.refreshAccessibilityStatus()
        }
        // Read through to the store so a switch reflects a rolled-back write
        // instead of the value the user just tapped.
        .onChange(of: settings.unlockTriggers) { oldValue, newValue in
            guard newValue.contains(.onSpace), !oldValue.contains(.onSpace) else { return }
            guard !credentials.accessibilityGranted else { return }
            credentials.requestAccessibility()
        }
        .onChange(of: isSessionUnlocked) { _, unlocked in
            guard !unlocked else { return }
            hidePreview()
        }
        .onDisappear { hidePreview() }
        // Enrollment, the password field and the scan all run in the notch,
        // outside this view's hierarchy, so nothing else prompts a re-check
        // once the window is closed.
        .onChange(of: FaceIDOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            credentials.refreshCredentialStatus()
            store.reloadIfUnlocked()
        }
        .confirmationDialog(
            "Delete this enrolled face?",
            isPresented: Binding(
                get: { identityPendingDeletion != nil },
                set: { if !$0 { identityPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: identityPendingDeletion
        ) { identity in
            Button("Delete", role: .destructive) { delete(identity) }
            Button("Cancel", role: .cancel) { identityPendingDeletion = nil }
        } message: { identity in
            Text("\"\(identity.name)\" will stop being recognized until you enroll them again.")
        }
    }

    // MARK: - General

    private var generalGroup: some View {
        SettingsGroup {
            SettingsRowContent(title: "Enable Face ID") {
                SettingsToggle(isOn: $settings.isEnabled)
            }
            SettingsGroupDivider()
            UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: settings.isEnabled)
            SettingsGroupDivider()
            displayPicker()
        }
    }

    /// Shown while "On space" is selected but Accessibility isn't granted —
    /// the same permission this feature needs to type the password, so the
    /// notice covers both.
    private var needsAccessibility: Bool {
        settings.isEnabled
            && settings.unlockTriggers.contains(.onSpace)
            && !credentials.accessibilityGranted
    }

    private var accessibilityNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCaption(text: "“On space” reads the keyboard directly to see the space key on the lock screen, which needs Accessibility — the same permission Face ID uses to type your password. Switch Notch on under Privacy & Security → Accessibility, then quit and reopen Notch.")
            Button("Open Accessibility settings") {
                credentials.requestAccessibility()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(SettingsMetrics.accent)
        }
    }

    private func displayPicker() -> some View {
        SettingsRowContent(title: "Display on") {
            SettingsMenuPickerPill(label: displayLabel) {
                Button("Main display") {
                    settings.preferredDisplayID = nil
                    settings.preferredDisplayName = nil
                }
                ForEach(screens.compactMap(NamedScreen.init), id: \.id) { screen in
                    Button(screen.name) {
                        settings.preferredDisplayID = screen.id
                        settings.preferredDisplayName = screen.name
                    }
                }
            }
        }
    }

    /// A connected screen with its stable ID already unwrapped, so the
    /// picker's `ForEach` doesn't need to filter inline.
    private struct NamedScreen {
        let id: String
        let name: String

        init?(_ screen: NSScreen) {
            guard let id = screen.faceIDDisplayID else { return nil }
            self.id = id
            self.name = screen.localizedName
        }
    }

    private var displayLabel: String {
        guard let targetID = settings.preferredDisplayID else { return "Main display" }
        if let connected = screens.first(where: { $0.faceIDDisplayID == targetID }) {
            return connected.localizedName
        }
        // Picked, but not currently connected — say so rather than showing
        // a bare ID or falling back to another display's name.
        guard let name = settings.preferredDisplayName else { return "Selected display (disconnected)" }
        return "\(name) (disconnected)"
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Behaviour")
            SettingsGroup {
                SettingsRowContent(title: "Retry on notch hover") {
                    SettingsToggle(isOn: $settings.retryOnHover)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Auto retry once after failure") {
                    SettingsToggle(isOn: $settings.autoRetryOnce)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Haptic feedback") {
                    SettingsToggle(isOn: $settings.hapticFeedbackEnabled)
                }
                SettingsGroupDivider()
                SettingsSteppedSliderRowContent(
                    title: "Face detection duration",
                    valueLabel: "\(settings.faceDetectionSeconds)s",
                    index: Binding(
                        get: { Double(settings.faceDetectionSeconds - FaceIDSettings.faceDetectionRange.lowerBound) },
                        set: { settings.faceDetectionSeconds = FaceIDSettings.faceDetectionRange.lowerBound + Int($0.rounded()) }
                    ),
                    stopCount: FaceIDSettings.faceDetectionRange.count
                )
            }
        }
    }

    // MARK: - Animation

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Animation")
            SettingsGroup {
                SettingsRowContent(title: "Show animation") {
                    SettingsToggle(isOn: $settings.showUnlockAnimation)
                }
                SettingsGroupDivider()
                UnlockAnimationPicker(
                    selection: $settings.unlockAnimationStyle,
                    isEnabled: settings.showUnlockAnimation
                )
            }
        }
    }

    // MARK: - Locked

    /// Stands in for Face, Password, Camera and Recognition at once: all four
    /// read data sealed under the session key, so none of them has anything
    /// truthful to show until it is open.
    private var lockedState: some View {
        SettingsEmptyStateView(
            icon: "lock.fill",
            message: "Session locked",
            buttonTitle: isUnlocking ? "Authenticating…" : "Unlock session",
            isButtonEnabled: !isUnlocking,
            caption: sessionError,
            action: unlock
        )
    }

    // MARK: - Face

    @ViewBuilder
    private var faceSection: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            if store.loadFailure != nil {
                unreadableState
            } else if store.identities.isEmpty {
                SettingsEmptyStateView(
                    icon: "faceid",
                    message: "Face enrollment",
                    buttonTitle: "Set up Face ID",
                    action: openFaceIDScreen
                )
            } else {
                faceEncryptedCard
                identitiesHeader

                ForEach(store.identities) { identity in
                    IdentityCard(
                        identity: identity,
                        isStale: identity.isStale(comparedTo: FaceRecognitionPipeline.shared.embedder),
                        isEnabled: enabledBinding(for: identity),
                        recapture: { openFaceIDScreen() },
                        delete: { identityPendingDeletion = identity }
                    )
                }

                if store.activeIdentities.isEmpty {
                    SettingsCaption(text: "No identities are enabled — Face ID won't recognize anyone until you switch one back on.")
                }

                if let writeError {
                    SettingsCaption(text: writeError)
                }
            }
        }
    }

    /// Mirrors the Password section's "Password encrypted" row — both refer
    /// to the same session key.
    private var faceEncryptedCard: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Face encrypted")
                        .font(SettingsMetrics.rowFont)
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Spacer(minLength: 8)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }

                Text("Enroll separate identities to use Face ID with multiple people, accessories (ex. glasses), facial expressions, or new lighting environments. This improves recognition quality.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsMetrics.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 12)
        }
    }

    private var identitiesHeader: some View {
        HStack(spacing: 0) {
            SettingsSectionTitle(text: "Identities")

            Button(action: openFaceIDScreen) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsMetrics.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Enroll another face")
            .padding(.trailing, SettingsMetrics.sectionTitleHorizontalInset)
            .padding(.top, SettingsMetrics.sectionTitleVerticalPadding)
        }
    }

    /// Session open but the encrypted store didn't decrypt. Deliberately
    /// offers no enroll or delete action, since a write here would replace
    /// faces still on disk.
    private var unreadableState: some View {
        VStack(spacing: SettingsMetrics.emptyStateSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SettingsMetrics.emptyStateIconSize, weight: .regular))
                .foregroundStyle(SettingsMetrics.qualityFairColor)

            Text("Enrolled faces couldn't be read")
                .font(SettingsMetrics.rowFont)
                .foregroundStyle(SettingsMetrics.textSecondary)

            SettingsCaption(text: store.loadFailure ?? "The stored data couldn't be decrypted with this session key.")
                .multilineTextAlignment(.center)

            SettingsCaption(text: "Nothing has been deleted, and Notch will not overwrite it — enrolling is blocked until this resolves. Quit and reopen Notch to retry. If it keeps failing, the session key no longer matches this data: remove the stored password below to clear both, then set up again.")
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.emptyStateMinHeight)
    }

    // MARK: - Password

    /// No password stored yet. Glance collects this in its onboarding window;
    /// this app collects it here, because its Face ID screen is the notch's
    /// own panel and a password field belongs behind a window that can become
    /// key.
    private var passwordSetupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Password")
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The password this Mac's login window expects. It is sealed with a key held in the keychain behind Touch ID and typed into the lock screen only after a face is recognized.")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        SecureField("Mac login password", text: $credentials.passwordInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(SettingsMetrics.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(SettingsMetrics.pickerPillFill))
                            .overlay(
                                Capsule().strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                            )
                            .onSubmit(savePassword)

                        SettingsPrimaryButton(
                            title: "Save",
                            isEnabled: !credentials.passwordInput.isEmpty,
                            compact: true,
                            action: savePassword
                        )
                    }
                }
                .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                .padding(.vertical, 12)
            }
        }
    }

    private var passwordUnlockedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Password")
            SettingsGroup {
                SettingsRowContent(title: "Password encrypted") {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }

                SettingsGroupDivider()

                SettingsSteppedSliderRowContent(
                    title: "Auto lock session",
                    valueLabel: settings.autoLockInterval.title,
                    index: Binding(
                        get: { settings.autoLockInterval.sliderIndex },
                        set: { settings.autoLockInterval = .from(sliderIndex: $0) }
                    ),
                    stopCount: AutoLockInterval.allCases.count
                )

                SettingsGroupDivider()

                SettingsActionRowContent(
                    title: "Remove password",
                    subtitle: "Also removes every enrolled face, since they're sealed under the same key.",
                    buttonTitle: "Remove",
                    isDestructive: true,
                    action: removePassword
                )
            }
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Camera")
            SettingsGroup {
                cameraPicker(title: "Default", selection: $settings.defaultCameraID)
                SettingsGroupDivider()
                cameraPicker(title: "Built-in display", selection: $settings.builtInDisplayCameraID)
                SettingsGroupDivider()
                cameraPicker(title: "External display", selection: $settings.externalDisplayCameraID)
            }
            .onChange(of: settings.defaultCameraID) { restartPreview() }
            .onChange(of: settings.builtInDisplayCameraID) { restartPreview() }
            .onChange(of: settings.externalDisplayCameraID) { restartPreview() }

            previewArea
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                        .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                )

            if isPreviewShown, let error = previewCamera.errorMessage {
                SettingsCaption(text: error)
            }
        }
    }

    private func cameraPicker(title: String, selection: Binding<String?>) -> some View {
        SettingsRowContent(title: title) {
            SettingsMenuPickerPill(label: cameraLabel(for: selection.wrappedValue)) {
                Button("System default") { selection.wrappedValue = nil }
                ForEach(cameras) { device in
                    Button(device.name) { selection.wrappedValue = device.id }
                }
            }
        }
    }

    /// Live feed, or a placeholder until "Show preview" is tapped — opening
    /// this page alone should never request camera access.
    @ViewBuilder
    private var previewArea: some View {
        if isPreviewShown {
            FaceIDCameraPreview(session: previewCamera.session)
        } else {
            ZStack {
                SettingsMetrics.rowColor
                SettingsPrimaryButton(title: "Show preview", action: showPreview)
            }
        }
    }

    private func showPreview() {
        isPreviewShown = true
        Task { await previewCamera.start() }
    }

    private func hidePreview() {
        guard isPreviewShown else { return }
        previewCamera.stop()
        isPreviewShown = false
    }

    /// The camera only re-resolves its device on `start()`, so restart it to
    /// reflect a new pick. No-op while hidden — picking a camera must not be
    /// what quietly turns it on.
    private func restartPreview() {
        guard isPreviewShown else { return }
        previewCamera.stop()
        Task { await previewCamera.start() }
    }

    /// Fired by the header's refresh control (see `HeaderTrailingActionKey`).
    private func refreshCameras() {
        cameras = FaceIDCameraCatalog.availableDevices()
    }

    private func cameraLabel(for id: String?) -> String {
        guard let id, let device = cameras.first(where: { $0.id == id }) else {
            return "System default"
        }
        return device.name
    }

    // MARK: - Recognition

    private var recognitionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Recognition")
            SettingsGroup {
                SettingsOptionSliderRowContent(
                    title: "Match confidence",
                    stepLabels: MatchConfidenceLevel.allCases.map(\.title),
                    index: matchConfidenceIndex,
                    stopCount: MatchConfidenceLevel.allCases.count
                )

                SettingsGroupDivider()

                SettingsOptionSliderRowContent(
                    title: "Detection distance",
                    stepLabels: DetectionDistanceLevel.allCases.map(\.title),
                    index: detectionDistanceIndex,
                    stopCount: DetectionDistanceLevel.allCases.count
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Liveness")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Liveness detection",
                        subtitle: "Checks that you're a live person, not a photo. May increase unlock time.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        SettingsToggle(isOn: $settings.livenessChecksEnabled)
                    }
                    SettingsGroupDivider()
                    LivenessModePicker(
                        selection: $settings.livenessMode,
                        isEnabled: settings.livenessChecksEnabled
                    )
                }
                if !settings.livenessChecksEnabled {
                    SettingsCaption(text: "With this off, a printed photo of an enrolled face is enough to unlock the Mac.")
                }
            }
        }
    }

    private var matchConfidenceIndex: Binding<Double> {
        Binding(
            get: { MatchConfidenceLevel.nearest(to: settings.matchThreshold).sliderIndex },
            set: { settings.matchThreshold = MatchConfidenceLevel.from(sliderIndex: $0).threshold }
        )
    }

    private var detectionDistanceIndex: Binding<Double> {
        Binding(
            get: { DetectionDistanceLevel.nearest(to: settings.minimumFaceWidth).sliderIndex },
            set: { settings.minimumFaceWidth = DetectionDistanceLevel.from(sliderIndex: $0).minimumFaceWidth }
        )
    }

    // MARK: - Actions

    /// Reads through to the store so the switch reflects a rolled-back write.
    private func enabledBinding(for identity: FaceIdentity) -> Binding<Bool> {
        Binding(
            get: { store.identities.first { $0.id == identity.id }?.isEnabled ?? true },
            set: { newValue in
                do {
                    try store.setEnabled(newValue, for: identity.id)
                    writeError = nil
                } catch {
                    writeError = error.localizedDescription
                }
            }
        )
    }

    private func delete(_ identity: FaceIdentity) {
        do {
            try store.delete(identity)
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
        identityPendingDeletion = nil
    }

    /// Enrollment and re-capture happen in the notch, so these hand the user
    /// across: select the Face ID screen and open the panel.
    private func openFaceIDScreen() {
        guard let state = (NSApp.delegate as? AppDelegate)?.state else { return }
        state.select(.faceID)
        state.expand()
    }

    private func unlock() {
        isUnlocking = true
        sessionError = nil
        Task {
            await credentials.unlockSession()
            sessionError = credentials.sessionError
            // The face store is encrypted under the same session key, so read
            // it now rather than leaving the Face section stuck at "locked".
            store.reloadIfUnlocked()
            isUnlocking = false
        }
    }

    private func savePassword() {
        let typed = credentials.passwordInput
        guard !typed.isEmpty else { return }
        Task {
            await credentials.savePassword()
            statusMessage = credentials.statusMessage
            store.reloadIfUnlocked()
        }
    }

    private func removePassword() {
        credentials.deleteEverything()
        statusMessage = credentials.statusMessage
        writeError = nil
    }
}

// MARK: - Identity card

/// One enrolled person: name pill and switch on the first line, quality
/// read-out and actions on the second. Built from `SettingsGroup` and the
/// shared row tokens so it matches every other settings page.
private struct IdentityCard: View {
    let identity: FaceIdentity
    let isStale: Bool
    @Binding var isEnabled: Bool
    let recapture: () -> Void
    let delete: () -> Void

    private var poorCount: Int {
        identity.samples.filter { $0.qualityTier == .poor }.count
    }

    private var ratedCount: Int {
        identity.samples.filter { $0.qualityTier != .unrated }.count
    }

    /// Share of samples that *aren't* in the red band, e.g. 3 low out of 18
    /// samples is 15/18 good → 83%.
    private var qualityPercentage: Int {
        let total = identity.samples.count
        guard total > 0 else { return 0 }
        return Int((Double(total - poorCount) / Double(total) * 100).rounded())
    }

    /// An enrollment saved before per-sample quality existed reports "not
    /// recorded" rather than a misleading 100%.
    private var qualityCaption: String {
        if identity.samples.isEmpty { return "No samples captured" }
        if ratedCount == 0 { return "Capture quality • not recorded" }
        return "Capture quality • \(qualityPercentage)%"
    }

    var body: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    namePill
                        .padding(.leading, -2)
                    Spacer(minLength: 8)
                    SettingsToggle(isOn: $isEnabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(qualityCaption)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textTertiary)

                    HStack(alignment: .center, spacing: 8) {
                        QualityTickStrip(samples: identity.samples)
                            .padding(.leading, 2)
                        Spacer(minLength: 12)
                        PillActionButton(title: "Recapture", action: recapture)
                        PillIconButton(systemImage: "trash", action: delete)
                            .help("Delete \(identity.name)")
                    }
                }
                // Dimmed rather than hidden while switched off: the person
                // is still enrolled, just not being matched against.
                .opacity(isEnabled ? 1 : 0.45)

                if isStale {
                    Text("Captured with a different recognition model — recapture before this face can unlock your Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsMetrics.qualityFairColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 12)
        }
    }

    private var namePill: some View {
        Text(identity.name)
            .font(SettingsMetrics.rowFont)
            .foregroundStyle(SettingsMetrics.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(SettingsMetrics.neutralButtonFill)
            .overlay(
                Capsule().strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// One tick per stored sample, colored by its band. Reads left-to-right in
/// capture order (not sorted by score) so a run of red points at the pose
/// that actually went badly.
private struct QualityTickStrip: View {
    let samples: [FaceSample]

    var body: some View {
        HStack(spacing: SettingsMetrics.qualityTickSpacing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(color(for: sample.qualityTier))
                    // maxWidth, not fixed, so more samples than a guided
                    // enrollment's 18 compress instead of overflowing.
                    .frame(maxWidth: SettingsMetrics.qualityTickWidth)
            }
        }
        .frame(width: stripWidth, height: SettingsMetrics.qualityTickHeight, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel("Capture quality for \(samples.count) samples")
    }

    /// Fixed rather than flexible: this strip shares a row with a `Spacer`
    /// and two buttons, and a `maxWidth` frame would negotiate against them
    /// for the slack instead of just sizing to its ticks.
    private var stripWidth: CGFloat {
        let tick = SettingsMetrics.qualityTickWidth
        let gap = SettingsMetrics.qualityTickSpacing
        let natural = CGFloat(samples.count) * (tick + gap) - gap
        return min(max(natural, 0), SettingsMetrics.qualityStripMaxWidth)
    }

    private func color(for tier: FaceSample.QualityTier) -> Color {
        switch tier {
        case .poor: SettingsMetrics.qualityPoorColor
        case .fair: SettingsMetrics.qualityFairColor
        case .good: SettingsMetrics.qualityGoodColor
        case .unrated: SettingsMetrics.qualityUnratedColor
        }
    }
}

/// Neutral capsule button matching the card's inner pills. Deliberately not
/// `SettingsPrimaryButton`: this sits next to a destructive action and
/// shouldn't read as the accent CTA.
private struct PillActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsMetrics.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(SettingsMetrics.neutralButtonFill)
                .overlay(
                    Capsule().strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The circular icon twin of `PillActionButton`, for the delete control.
private struct PillIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(SettingsMetrics.textPrimary)
                .frame(width: 28, height: 28)
                .background(SettingsMetrics.neutralButtonFill)
                .overlay(
                    Circle().strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Named stops

/// The three selectable points on the "Match confidence" slider — named
/// rather than exposing the raw cosine-similarity threshold directly.
///
/// Glance's page has the same three names over 0.58/0.63/0.68, which don't
/// include its own 0.66 default; these are centred on this port's stored
/// default instead, so the middle stop is honestly "Default".
private enum MatchConfidenceLevel: Int, CaseIterable {
    case lessStrict, standard, moreStrict

    var title: String {
        switch self {
        case .lessStrict: "Less strict"
        case .standard: "Default"
        case .moreStrict: "More strict"
        }
    }

    var threshold: Float {
        switch self {
        case .lessStrict: 0.60
        case .standard: 0.66
        case .moreStrict: 0.72
        }
    }

    /// Position in `allCases` — same role as `AutoLockInterval.sliderIndex`.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to threshold: Float) -> Self {
        allCases.min { abs($0.threshold - threshold) < abs($1.threshold - threshold) } ?? .standard
    }
}

/// The three selectable points on the "Detection distance" slider.
private enum DetectionDistanceLevel: Int, CaseIterable {
    case close, standard, far

    var title: String {
        switch self {
        case .close: "Close"
        case .standard: "Default"
        case .far: "Far"
        }
    }

    var minimumFaceWidth: Float {
        switch self {
        case .close: 0.25
        case .standard: 0.21
        case .far: 0.16
        }
    }

    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to width: Float) -> Self {
        allCases.min { abs($0.minimumFaceWidth - width) < abs($1.minimumFaceWidth - width) } ?? .standard
    }
}
