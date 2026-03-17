import Foundation

/// Lightweight bridge to pass scroll fraction from editor to preview
/// without triggering SwiftUI view updates (avoids jitter).
public final class ScrollBridge {
    public var fraction: CGFloat = 0
    public var onScroll: ((CGFloat) -> Void)?

    public init() {}
}
