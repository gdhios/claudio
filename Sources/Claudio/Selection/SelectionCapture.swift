import AppKit
import ApplicationServices

@MainActor
enum SelectionCapture {
    /// Tries the Accessibility API first (instant, doesn't touch the
    /// clipboard), then falls back to a simulated ⌘C (reliable everywhere,
    /// Chrome/Electron included).
    static func capture() async -> String? {
        if let text = viaAccessibility(), !text.isEmpty {
            return text
        }
        return await viaSimulatedCopy()
    }

    private static func viaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String,
              !text.isEmpty else { return nil }
        return text
    }

    private static func viaSimulatedCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        Keystroke.simulate(virtualKey: Keystroke.keyC, flags: .maskCommand)

        let deadline = Date().addingTimeInterval(Constants.copyTimeout)
        while Date() < deadline {
            if pasteboard.changeCount != before {
                let text = pasteboard.string(forType: .string)
                return (text?.isEmpty == false) ? text : nil
            }
            try? await Task.sleep(nanoseconds: Constants.copyPollIntervalNs)
        }
        return nil  // nothing was copied: probably no selection
    }
}
