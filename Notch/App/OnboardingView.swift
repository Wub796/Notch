import SwiftUI

/// Single-page welcome: what the app does, how to talk to it, and the two
/// optional permissions — ending in one clear call to action.
struct OnboardingView: View {
    let state: NotchState
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                appMark
                    .padding(.top, 34)

                Text("Welcome to Notch")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your notch, doing more.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow(
                    icon: "music.note",
                    tint: Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255),
                    title: "Media & live lyrics",
                    caption: "Any player, synced lyrics, artwork-tinted controls."
                )
                featureRow(
                    icon: "tray.and.arrow.down.fill",
                    tint: .blue,
                    title: "Shelf & AirDrop",
                    caption: "Drop files onto the notch — hold, drag out, or send."
                )
                featureRow(
                    icon: "calendar",
                    tint: .orange,
                    title: "Schedule",
                    caption: "The next 24 hours, with one-click meeting joins."
                )
                featureRow(
                    icon: "bolt.badge.clock",
                    tint: Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255),
                    title: "Live activities",
                    caption: "Volume, battery, meetings, and now playing — at a glance."
                )
            }
            .padding(.horizontal, 44)
            .padding(.top, 26)

            gestureHints
                .padding(.top, 22)

            Spacer(minLength: 16)

            permissions
                .padding(.horizontal, 44)

            Button(action: onFinish) {
                Text("Start Using Notch")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 44)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .frame(width: 460, height: 620)
        .preferredColorScheme(.dark)
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 72, height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }

    private func featureRow(icon: String, tint: Color, title: String, caption: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var gestureHints: some View {
        HStack(spacing: 6) {
            hint("cursorarrow.motionlines", "Hover to peek")
            hint("cursorarrow.click", "Click to open")
            hint("arrow.down.doc", "Drop to shelve")
        }
    }

    private func hint(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.07)))
    }

    @State private var refreshToken = 0

    private var permissions: some View {
        let calendarGranted = IntegrationPermissions.Integration.calendar.status == .granted
        let locationGranted = IntegrationPermissions.Integration.location.status == .granted

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                permissionButton(
                    calendarGranted ? "checkmark.circle.fill" : "calendar",
                    calendarGranted ? "Calendar Enabled" : "Enable Calendar",
                    isGranted: calendarGranted
                ) {
                    IntegrationPermissions.Integration.calendar.request {
                        refreshToken += 1
                        state.calendar.refresh()
                    }
                }
                permissionButton(
                    locationGranted ? "checkmark.circle.fill" : "location.fill",
                    locationGranted ? "Weather Enabled" : "Enable Weather",
                    isGranted: locationGranted
                ) {
                    IntegrationPermissions.Integration.location.request {
                        refreshToken += 1
                        state.weather.refresh(force: true)
                    }
                }
            }
            Text("Both are optional — you can grant or revoke them anytime in System Settings.")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
        }
        .id(refreshToken)
    }

    private func permissionButton(
        _ icon: String,
        _ title: String,
        isGranted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isGranted ? .green : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isGranted ? Color.green.opacity(0.15) : .white.opacity(0.09))
                }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isGranted)
    }
}
