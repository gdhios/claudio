import AppKit
import ApplicationServices

/// Snaps the frontmost window through the Accessibility API. The geometry is
/// `WindowLayout`'s; this is only the transport — find the window, read its
/// frame, write the target back — and it reuses the Accessibility permission
/// the app already needs to read selections and paste.
@MainActor
enum WindowMover {
    /// Snap the frontmost window to `layout`, on the display it already sits on.
    static func apply(_ layout: WindowLayout) {
        guard let target = frontmostWindow() else { return }
        setFrame(layout.frame(in: target.visible, current: target.frame), on: target.window)
    }

    /// Send the frontmost window to the next display, keeping the placement it
    /// had on the current one: a half stays a half, a maximized window stays
    /// maximized. Does nothing with a single display.
    static func moveToNextScreen() {
        guard let target = frontmostWindow() else { return }
        let height = primaryDisplayHeight()
        let areas = NSScreen.screens.map {
            ScreenGeometry.axRect(fromCocoa: $0.visibleFrame, primaryHeight: height)
        }
        guard let next = ScreenGeometry.next(after: target.visible, in: areas) else { return }
        setFrame(ScreenGeometry.reproject(target.frame, from: target.visible, to: next),
                 on: target.window)
    }

    // MARK: - Frontmost window

    /// What both commands act on: the frontmost app's focused window, its frame
    /// and the usable area of the display it sits on, all in AX coordinates.
    /// Nil when the permission is missing — it is then asked for — when Claudio
    /// itself is in front, or when the window can't be read.
    private static func frontmostWindow() -> (window: AXUIElement, frame: CGRect, visible: CGRect)? {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            AccessibilityPermission.showExplanation()
            return nil
        }
        // Skip Claudio's own windows: nothing to snap, and the frontmost app is
        // whoever was in front when the shortcut fired.
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let window = focusedWindow(of: app),
              let current = frame(of: window),
              let screen = screenContaining(current) ?? NSScreen.main else { return nil }
        let visible = ScreenGeometry.axRect(fromCocoa: screen.visibleFrame,
                                            primaryHeight: primaryDisplayHeight())
        return (window, current, visible)
    }

    private static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focusedRef,
           CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            return (focusedRef as! AXUIElement)
        }
        // No focused window reported: fall back to the app's first window.
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            return windows.first
        }
        return nil
    }

    // MARK: - Read and write the frame, in AX coordinates

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func setFrame(_ frame: CGRect, on window: AXUIElement) {
        var position = frame.origin
        var size = frame.size
        // Size, then position, then size again: a growing window clamped by its
        // old position, or a shrinking one, both end up at the intended frame.
        writeSize(&size, on: window)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        writeSize(&size, on: window)
    }

    private static func writeSize(_ size: inout CGSize, on window: AXUIElement) {
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: - Which screen

    /// The screen the window sits on, by its center. `current` is in AX
    /// coordinates; `NSScreen` frames are Cocoa, so compare in AX space.
    private static func screenContaining(_ current: CGRect) -> NSScreen? {
        let height = primaryDisplayHeight()
        let center = CGPoint(x: current.midX, y: current.midY)
        return NSScreen.screens.first { screen in
            ScreenGeometry.axRect(fromCocoa: screen.frame, primaryHeight: height).contains(center)
        }
    }

    /// Height of the display at the Cocoa origin — the reference for the flip,
    /// as the previews already assume (`PreviewMode`).
    private static func primaryDisplayHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
}
