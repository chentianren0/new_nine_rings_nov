import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension View {
    /// Orbit, pan and zoom the camera.
    ///
    /// On iPhone and iPad: drag with one finger to orbit, two to pan, and pinch to zoom.
    /// On the Mac: drag to orbit, Option-drag or scroll on a trackpad to pan, and pinch or use a mouse wheel to zoom.
    func cameraGestures(_ rig: CameraRig) -> some View {
        modifier(CameraGestures(rig: rig))
    }
}

#if os(macOS)
private struct CameraGestures: ViewModifier {
    let rig: CameraRig
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var window: NSWindow?
    @State private var scrollMonitor: Any?

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta = CGSize(width: value.translation.width - lastDrag.width, height: value.translation.height - lastDrag.height)
                        lastDrag = value.translation
                        if NSEvent.modifierFlags.contains(.option) {
                            rig.pan(by: delta)
                        } else {
                            rig.orbit(by: delta)
                        }
                    }
                    .onEnded { _ in lastDrag = .zero }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        rig.zoom(by: value.magnification / lastMagnification)
                        lastMagnification = value.magnification
                    }
                    .onEnded { _ in lastMagnification = 1 }
            )
            .background(WindowReader(window: $window))
            .onAppear(perform: startScrolling)
            .onDisappear(perform: stopScrolling)
    }

    /// Scroll events reach no SwiftUI gesture, so they are taken from the window's event stream.
    private func startScrolling() {
        guard scrollMonitor == nil else { return }
        let rig = rig
        let window = $window
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let own = window.wrappedValue, event.window === own else { return event }
            if event.hasPreciseScrollingDeltas {
                // A trackpad: two fingers slide the toy.
                rig.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
            } else {
                // A mouse wheel: zoom.
                rig.zoom(by: pow(1.1, event.scrollingDeltaY))
            }
            return nil
        }
    }

    private func stopScrolling() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }
}

/// Finds the window a view is in.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.report = { window = $0 }
        return view
    }

    func updateNSView(_ view: WindowReportingView, context: Context) {}
}

private final class WindowReportingView: NSView {
    var report: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // AppKit keeps the view's window as an unowned reference; it is read here, as the view joins it.
        report?(unsafe window)
    }
}
#else
private struct CameraGestures: ViewModifier {
    let rig: CameraRig

    func body(content: Content) -> some View {
        content
            .gesture(PanRecognizer(touches: 1...1) { rig.orbit(by: $0) })
            .gesture(PanRecognizer(touches: 2...2) { rig.pan(by: $0) })
            .gesture(PinchRecognizer { rig.zoom(by: $0) })
    }
}

/// A pan with a given number of fingers, reported as the distance moved since the last report.
private struct PanRecognizer: UIGestureRecognizerRepresentable {
    let touches: ClosedRange<Int>
    let moved: (CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = touches.lowerBound
        recognizer.maximumNumberOfTouches = touches.upperBound
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        moved(CGSize(width: translation.x, height: translation.y))
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SimultaneousDelegate {
        SimultaneousDelegate()
    }
}

/// A pinch, reported as the change in scale since the last report.
private struct PinchRecognizer: UIGestureRecognizerRepresentable {
    let scaled: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        scaled(recognizer.scale)
        recognizer.scale = 1
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SimultaneousDelegate {
        SimultaneousDelegate()
    }
}

/// Lets panning and pinching run together.
private final class SimultaneousDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
