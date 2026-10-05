@testable import Claudio

extension BridgeDispatcher {
    /// A dispatcher whose keys go nowhere: what a bridge that is never
    /// started would do with them.
    static var doingNothing: BridgeDispatcher {
        BridgeDispatcher(triggerAction: { _ in }, triggerFree: {}, triggerPalette: {},
                         triggerWhatsPlaying: {},
                         dictationDown: { _, _ in }, dictationUp: {}, dictationCancel: {},
                         applyLayout: { _ in }, nextScreen: {}, openSettings: {})
    }
}
