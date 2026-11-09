import AppKit
import SwiftUI

/// Travel directions for the guided enrollment light sweeps.
/// Ported from Glance (`EnrollmentDirectionSweep.swift`, MIT © Jonathan Zhou).
enum FaceIDSweepDirection: CaseIterable, Hashable {
    case left, right, up, down, topLeft, topRight, bottomLeft, bottomRight

    /// Unit travel vector in screen space (x right, y down); sweep originates on the
    /// opposite side, e.g. `.left` travels right -> left.
    var travel: CGVector {
        let d = CGFloat(1 / sqrt(2.0))
        switch self {
        case .left:        return CGVector(dx: -1, dy:  0)
        case .right:       return CGVector(dx:  1, dy:  0)
        case .up:          return CGVector(dx:  0, dy: -1)
        case .down:        return CGVector(dx:  0, dy:  1)
        case .topLeft:     return CGVector(dx: -d, dy: -d)
        case .topRight:    return CGVector(dx:  d, dy: -d)
        case .bottomLeft:  return CGVector(dx: -d, dy:  d)
        case .bottomRight: return CGVector(dx:  d, dy:  d)
        }
    }

    init?(pose: FaceIDPose) {
        switch pose {
        case .center:      return nil
        case .left:        self = .left
        case .right:       self = .right
        case .top:         self = .up
        case .bottom:      self = .down
        case .topLeft:     self = .topLeft
        case .topRight:    self = .topRight
        case .bottomLeft:  self = .bottomLeft
        case .bottomRight: self = .bottomRight
        }
    }
}

/// Layered blurred ribbons that sweep toward an enrollment direction;
/// the motion itself is the cue.
struct FaceIDDirectionSweep: View {
    let direction: FaceIDSweepDirection

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Self.specs) { spec in
                    SweepStreak(
                        spec: spec,
                        direction: direction,
                        canvasSize: geo.size
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(FaceIDMetrics.sweepMasterOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Streak specs

private struct StreakSpec: Identifiable {
    let id: Int
    let thickness: CGFloat
    let lengthFactor: CGFloat
    let blurScale: CGFloat
    let peakOpacity: Double
    let duration: Double
    let delay: Double
    let lateral: CGFloat
    let bow: CGFloat
    let fadeOutAt: Double
    let hasHighlight: Bool
    let isVivid: Bool
}

extension FaceIDDirectionSweep {
    fileprivate static let specs: [StreakSpec] = makeSpecs()

    private static func makeSpecs() -> [StreakSpec] {
        let count = 42
        let laterals = (0..<count).map { index -> CGFloat in
            let t = CGFloat(index) / CGFloat(count - 1)
            return -0.86 + t * 1.72
        }
        return laterals.enumerated().map { index, lateral in
            let lane = index % 7
            let edgeFade = 1 - abs(Double(lateral)) * 0.22
            let isVivid = index % 6 == 1 || index % 6 == 4
            let heavyBlur = index % 4 != 0
            let blurScale: CGFloat = [1.35, 1.16, 0.96, 1.22, 0.82, 1.32, 1.02][lane]
                * (heavyBlur ? 2.6 : 1.1)
            let peakBase: Double = [0.58, 0.72, 0.80, 0.52, 0.66, 0.42, 0.48][lane]
            return StreakSpec(
                id: index,
                thickness: [310, 190, 105, 155, 72, 230, 88][lane],
                lengthFactor: [1.16, 0.94, 0.72, 0.86, 0.54, 1.04, 0.62][lane],
                blurScale: blurScale,
                peakOpacity: peakBase * edgeFade * (isVivid ? 1.4 : 1),
                duration: [1.22, 1.08, 0.98, 1.16, 0.94, 1.28, 1.04][lane],
                delay: [0.00, 0.03, 0.06, 0.015, 0.08, 0.04, 0.065][lane]
                    + Double(index % 4) * 0.008,
                lateral: lateral,
                bow: [0.18, -0.14, 0.10, -0.22, 0.26, 0.08, -0.12][lane],
                fadeOutAt: 1,
                hasHighlight: isVivid || lane == 2 || lane == 4,
                isVivid: isVivid
            )
        }
    }
}

// MARK: - Geometry

private struct SweepGeometry {
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint
    let canvasSize: CGSize
    let length: CGFloat
    let rotationDrift: Double

    init(spec: StreakSpec, direction: FaceIDSweepDirection, canvasSize: CGSize) {
        self.canvasSize = canvasSize
        let travel = direction.travel
        let perp = CGVector(dx: -travel.dy, dy: travel.dx)
        let shortEdge = min(canvasSize.width, canvasSize.height)
        let diagonal = hypot(canvasSize.width, canvasSize.height)
        let startSpan = diagonal * 0.58
        let endSpan = diagonal * 0.50
        length = max(shortEdge * spec.lengthFactor * 0.55, 180)
        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2
        let perpExtent = abs(perp.dx) * canvasSize.width + abs(perp.dy) * canvasSize.height
        let lateral = spec.lateral * perpExtent * 0.46
        start = CGPoint(
            x: cx - travel.dx * startSpan + perp.dx * lateral,
            y: cy - travel.dy * startSpan + perp.dy * lateral
        )
        end = CGPoint(
            x: cx + travel.dx * endSpan + perp.dx * lateral,
            y: cy + travel.dy * endSpan + perp.dy * lateral
        )
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let bow = spec.bow * shortEdge * 0.20
        control = CGPoint(x: mid.x + perp.dx * bow, y: mid.y + perp.dy * bow)
        rotationDrift = Double(spec.bow.sign == .minus ? -0.05 : 0.05)
    }

    func point(at t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    func heading(at t: Double) -> Double {
        let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        return atan2(dy, dx)
    }

    func opacity(at t: Double, peak: Double, fadeOutAt: Double) -> Double {
        let fadeInEnd = 0.07
        let fadeOutStart = 0.7
        if t <= 0 || t >= fadeOutAt { return 0 }
        if t < fadeInEnd {
            let u = t / fadeInEnd
            return peak * (u * u * (3 - 2 * u))
        }
        if t > fadeOutStart {
            let span = max(fadeOutAt - fadeOutStart, 0.001)
            let u = (t - fadeOutStart) / span
            let s = u * u * (3 - 2 * u)
            return peak * (1 - s)
        }
        return peak
    }
}

// MARK: - Motion

private struct SweepMovingContainer<Content: View>: View, Animatable {
    var progress: Double
    let geometry: SweepGeometry
    let peakOpacity: Double
    let fadeOutAt: Double
    let content: Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let t = min(max(progress, 0), 1)
        let point = geometry.point(at: t)
        let cx = geometry.canvasSize.width / 2
        let cy = geometry.canvasSize.height / 2
        content
            .rotationEffect(.radians(geometry.heading(at: t) + geometry.rotationDrift * t))
            .offset(x: point.x - cx, y: point.y - cy)
            .opacity(geometry.opacity(at: t, peak: peakOpacity, fadeOutAt: fadeOutAt))
    }
}

// MARK: - Streak view

private struct SweepStreak: View {
    let spec: StreakSpec
    let direction: FaceIDSweepDirection
    let canvasSize: CGSize

    @State private var progress: Double = 0

    var body: some View {
        let geometry = SweepGeometry(spec: spec, direction: direction, canvasSize: canvasSize)
        SweepMovingContainer(
            progress: progress,
            geometry: geometry,
            peakOpacity: spec.peakOpacity,
            fadeOutAt: spec.fadeOutAt,
            content: layers(length: geometry.length)
        )
        .onAppear { runSweep() }
    }

    private func layers(length: CGFloat) -> some View {
        ZStack {
            streakLayer(
                length: length,
                thickness: spec.thickness * 2.35,
                blur: 78 * spec.blurScale,
                opacity: spec.isVivid ? 0.28 : 0.16,
                colors: [FaceIDAccent.accent, FaceIDAccent.bright]
            )
            streakLayer(
                length: length,
                thickness: spec.thickness,
                blur: 34 * spec.blurScale,
                opacity: spec.isVivid ? 0.48 : 0.30,
                colors: spec.isVivid
                    ? [FaceIDAccent.bright, FaceIDAccent.pale]
                    : [FaceIDAccent.accent, FaceIDAccent.bright]
            )
            streakLayer(
                length: length,
                thickness: spec.thickness * 0.42,
                blur: 14 * spec.blurScale,
                opacity: spec.isVivid ? 0.62 : 0.38,
                colors: [FaceIDAccent.bright, FaceIDAccent.pale]
            )
            if spec.hasHighlight {
                streakLayer(
                    length: length * 0.72,
                    thickness: spec.thickness * 0.12,
                    blur: 6,
                    opacity: spec.isVivid ? 0.36 : 0.20,
                    colors: [FaceIDAccent.pale, Color.white]
                )
            }
        }
        .compositingGroup()
    }

    private func streakLayer(
        length: CGFloat,
        thickness: CGFloat,
        blur: CGFloat,
        opacity: Double,
        colors: [Color]
    ) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: colors[0].opacity(0), location: 0),
                        .init(color: colors[0].opacity(0.6), location: 0.18),
                        .init(color: colors[1], location: 0.55),
                        .init(color: colors[1].opacity(0.85), location: 0.82),
                        .init(color: colors[1].opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: length, height: thickness)
            .blur(radius: blur)
            .opacity(opacity)
    }

    private func runSweep() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        Task { @MainActor in
            withAnimation(
                .timingCurve(0.68, 0.0, 0.32, 1.0, duration: spec.duration)
                .delay(spec.delay)
            ) {
                progress = 1
            }
        }
    }
}

// MARK: - Sweep Window Controller

/// Controls the click-through full-screen window for enrollment direction sweeps.
/// Ported from Glance (`EnrollmentSweepWindowController.swift`, MIT © Jonathan Zhou).
@MainActor
final class FaceIDEnrollmentSweepWindowController {
    @Observable
    final class Host {
        var isPresented = false
        let session: FaceIDEnrollmentSession

        init(session: FaceIDEnrollmentSession) {
            self.session = session
        }
    }

    private var window: NSPanel?
    private var host: Host?
    private var dismissTask: Task<Void, Never>?

    func present(for session: FaceIDEnrollmentSession) {
        dismissTask?.cancel()
        dismissTask = nil
        tearDownWindow()

        guard let screen = FaceIDGeometry.preferredScreen() ?? NSScreen.main else { return }

        let host = Host(session: session)
        host.isPresented = true

        let hostingView = NSHostingView(rootView: FaceIDEnrollmentSweepOverlay(host: host))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let window = makePanel(on: screen, contentView: hostingView)
        window.orderFrontRegardless()

        self.host = host
        self.window = window
    }

    func dismiss() {
        dismissTask?.cancel()
        guard window != nil, let host else {
            tearDownWindow()
            return
        }
        host.isPresented = false
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FaceIDMetrics.sweepFadeOut))
            guard !Task.isCancelled else { return }
            tearDownWindow()
            dismissTask = nil
        }
    }

    deinit {
        dismissTask?.cancel()
    }

    private func tearDownWindow() {
        window?.orderOut(nil)
        window = nil
        host = nil
    }

    private func makePanel(on screen: NSScreen, contentView: NSView) -> NSPanel {
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        // One level below NotchPanel's `.statusBar` (25) so notch content composites on top.
        window.level = .mainMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = contentView
        window.setFrame(screen.frame, display: true)
        return window
    }
}

// MARK: - Sweep Overlay Root

private struct FaceIDEnrollmentSweepOverlay: View {
    @Bindable var host: FaceIDEnrollmentSweepWindowController.Host
    @State private var playingDirection: FaceIDSweepDirection?
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        let pose = host.session.currentPose
        let presented = host.isPresented
        let isCapturing = host.session.phase == .capturing
        let tooFar = host.session.isTooFar
        let checkmark = host.session.showCheckmark
        let direction = FaceIDSweepDirection(pose: pose)
        let canPlay = presented && isCapturing && !tooFar && !checkmark && !host.session.enrollmentComplete
        let isVisible = canPlay && playingDirection != nil

        ZStack {
            Color.clear
            if isVisible, let playingDirection {
                FaceIDDirectionSweep(direction: playingDirection)
                    .id(playingDirection)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: direction, initial: true) { _, newDirection in
            scheduleSweep(newDirection, canPlay: canPlay)
        }
        .onChange(of: canPlay) { _, playable in
            if !playable {
                playTask?.cancel()
                playingDirection = nil
            } else {
                scheduleSweep(direction, canPlay: true)
            }
        }
        .animation(.easeInOut(duration: FaceIDMetrics.sweepDirectionCrossfade), value: playingDirection)
        .animation(
            .easeInOut(
                duration: isVisible
                    ? FaceIDMetrics.sweepFadeIn
                    : FaceIDMetrics.sweepFadeOut
            ),
            value: isVisible
        )
        .allowsHitTesting(false)
        .onDisappear {
            playTask?.cancel()
            playTask = nil
        }
    }

    private func scheduleSweep(_ newDirection: FaceIDSweepDirection?, canPlay: Bool) {
        playTask?.cancel()
        guard canPlay, let newDirection else {
            playingDirection = nil
            return
        }
        playingDirection = nil
        playTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FaceIDMetrics.sweepPoseDelay))
            guard !Task.isCancelled else { return }
            playingDirection = newDirection
        }
    }
}
