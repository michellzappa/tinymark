import Foundation

/// Lightweight bridge to pass scroll fraction from editor to preview
/// without triggering SwiftUI view updates (avoids jitter).
final class ScrollBridge {
    var fraction: CGFloat = 0
    var onScroll: ((CGFloat) -> Void)?
}
