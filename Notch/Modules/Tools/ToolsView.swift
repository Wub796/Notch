import SwiftUI

/// The Tools tab: audio output routing, accessory batteries, a countdown
/// timer, eye-break reminders, and favourite Shortcuts — the utility
/// modules from Sapphire that belong together.
struct ToolsView: View {
    let state: NotchState

    var body: some View {
        // Budget: NotchState.moduleContentSize, about 838 x 240 at the
        // default panel size. Each column is a card so the four read as four
        // things rather than one dense field of text.
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Tools", subtitle: "Output, accessories, timers and shortcuts")

            HStack(alignment: .top, spacing: NotchTheme.Space.m) {
                column { audioColumn }
                    .frame(maxWidth: .infinity, alignment: .leading)

                column { accessoriesColumn }
                    .frame(maxWidth: .infinity, alignment: .leading)

                column { timerColumn }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if state.settings.showQuickActions {
                    column { quickActionsColumn }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// One column of the tools grid, in the shared card treatment.
    private func column<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(NotchTheme.Space.m)
            .frame(maxHeight: .infinity, alignment: .top)
            .notchCard()
    }

    // MARK: - Audio output

    private var audioColumn: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            sectionLabel("OUTPUT")

            if state.audio.devices.isEmpty {
                placeholder("No output devices")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(state.audio.devices) { device in
                            deviceRow(device)
                        }
                    }
                }
                volumeRow
            }
        }
    }

    /// Live output volume for the selected device, with a mute toggle.
    private var volumeRow: some View {
        HStack(spacing: 8) {
            Button {
                state.audio.toggleMute()
            } label: {
                Image(systemName: state.audio.isMuted
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(
                        state.audio.isMuted ? .red : NotchTheme.inkSecondary
                    )
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(state.audio.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { Double(state.audio.volume) },
                    set: { state.audio.setVolume(Float($0)) }
                ),
                in: 0 ... 1
            )
            .controlSize(.mini)
            .tint(NotchTheme.inkPrimary)
            .disabled(state.audio.isMuted)
            .opacity(state.audio.isMuted ? 0.4 : 1)
            .accessibilityLabel("Output volume")
        }
        .padding(.top, 2)
    }

    private func deviceRow(_ device: AudioOutputManager.Device) -> some View {
        let isCurrent = device.id == state.audio.currentDeviceID
        return Button {
            withAnimation(NotchAnimations.content) {
                state.audio.select(device)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrent ? NotchTheme.battery : NotchTheme.inkSecondary)
                    .frame(width: 16)
                Text(device.name)
                    .font(.notchCaption.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? NotchTheme.inkPrimary : NotchTheme.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NotchTheme.battery)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.thumb, style: .continuous)
                    .fill(isCurrent ? NotchTheme.surfaceHover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(device.name)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    // MARK: - Accessories

    private var accessoriesColumn: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            sectionLabel("ACCESSORIES")

            if state.bluetooth.devices.isEmpty {
                placeholder("Nothing connected")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.bluetooth.devices) { device in
                        accessoryRow(device)
                    }
                }
            }
        }
    }

    private func accessoryRow(_ device: BluetoothBatteryMonitor.Device) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(NotchTheme.inkSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.notchCaption.weight(.bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let percent = device.percent {
                        levelChip(nil, percent)
                    }
                    if let left = device.leftPercent { levelChip("L", left) }
                    if let right = device.rightPercent { levelChip("R", right) }
                    if let caseLevel = device.casePercent { levelChip("C", caseLevel) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.name)
        .accessibilityValue(device.lowestPercent.map { "\($0) percent" } ?? "unknown")
    }

    private func levelChip(_ prefix: String?, _ percent: Int) -> some View {
        HStack(spacing: 2) {
            if let prefix {
                Text(prefix)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
            Text("\(percent)%")
                .font(.notchFootnote.weight(.bold).monospacedDigit())
                .foregroundStyle(percent <= 20 ? .red : NotchTheme.inkPrimary.opacity(0.9))
        }
    }

    // MARK: - Timer, eye break, shortcuts

    private var timerColumn: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            sectionLabel("TIMER")

            if state.timer.isRunning {
                HStack(spacing: 10) {
                    Text(TimerManager.timeString(state.timer.remaining))
                        .font(.notchTitle.monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .contentTransition(.numericText())

                    Button {
                        state.timer.togglePause()
                    } label: {
                        Image(systemName: state.timer.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(NotchTheme.surface))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(state.timer.isPaused ? "Resume timer" : "Pause timer")

                    Button {
                        withAnimation(NotchAnimations.content) { state.timer.cancel() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(NotchTheme.surface))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Cancel timer")
                }
            } else {
                HStack(spacing: 5) {
                    ForEach([1, 5, 10, 25], id: \.self) { minutes in
                        Button {
                            withAnimation(NotchAnimations.content) {
                                state.timer.start(minutes: minutes)
                            }
                        } label: {
                            Text("\(minutes)m")
                                .font(.notchCaption.weight(.bold).monospacedDigit())
                                .foregroundStyle(NotchTheme.inkPrimary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(NotchTheme.surface))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("\(minutes) minute timer")
                    }
                }
            }

            eyeBreakRow
            shortcutsRow
        }
    }

    private var eyeBreakRow: some View {
        Button {
            withAnimation(NotchAnimations.content) {
                state.eyeBreak.setEnabled(!state.eyeBreak.isEnabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: state.eyeBreak.isEnabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        state.eyeBreak.isEnabled ? NotchTheme.battery : NotchTheme.inkMuted
                    )
                Text(state.eyeBreak.isEnabled
                    ? (state.eyeBreak.isOnBreak
                        ? "Look away…"
                        : "Break in \(Int(state.eyeBreak.timeUntilBreak / 60) + 1) min")
                    : "Eye breaks off")
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Eye break reminders")
        .accessibilityValue(state.eyeBreak.isEnabled ? "on" : "off")
    }

    @ViewBuilder
    private var shortcutsRow: some View {
        if !state.shortcuts.favorites.isEmpty {
            HStack(spacing: 5) {
                ForEach(state.shortcuts.favorites.prefix(3), id: \.self) { name in
                    Button {
                        state.shortcuts.run(name)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.shortcuts.runningName == name
                                ? "hourglass"
                                : "square.stack.3d.up.fill")
                                .font(.system(size: 10))
                            Text(name)
                                .font(.notchFootnote)
                                .lineLimit(1)
                        }
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(NotchTheme.surfaceHover))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Run shortcut \(name)")
                }
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionsColumn: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            sectionLabel("QUICK ACTIONS")

            VStack(alignment: .leading, spacing: 4) {
                actionButton(
                    state.quickActions.isDarkMode ? "sun.max.fill" : "moon.fill",
                    state.quickActions.isDarkMode ? "Light Mode" : "Dark Mode"
                ) {
                    state.quickActions.toggleAppearance()
                }

                actionButton("lock.fill", "Lock Screen") {
                    state.quickActions.lockScreen()
                }

                actionButton("display", "Sleep Display") {
                    state.quickActions.sleepDisplay()
                }

                actionButton(
                    "trash.fill",
                    state.quickActions.trashItemCount > 0
                        ? "Empty Trash (\(state.quickActions.trashItemCount))"
                        : "Trash Empty",
                    isEnabled: state.quickActions.trashItemCount > 0
                ) {
                    state.quickActions.emptyTrash()
                }

                // These all go through AppleScript, which fails silently when
                // Automation consent was declined; say so rather than letting
                // the button look inert.
                if let error = state.quickActions.lastError {
                    Text(error)
                        .font(.notchFootnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 146, alignment: .leading)
                }
            }
        }
        .onAppear { state.quickActions.refresh() }
    }

    private func actionButton(
        _ systemImage: String,
        _ title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title)
                    .font(.notchCaption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? NotchTheme.inkSecondary : NotchTheme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 146, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.thumb, style: .continuous)
                    .fill(NotchTheme.surfaceHover)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    // MARK: - Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.notchEyebrow)
            .tracking(0.9)
            .foregroundStyle(NotchTheme.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.notchCaption)
            .foregroundStyle(NotchTheme.inkMuted)
            .padding(.top, 2)
    }
}
