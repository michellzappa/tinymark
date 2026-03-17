import SwiftUI
import AppKit

/// A thin NSSplitView wrapper with a wider invisible drag target.
public struct EditorSplitView<Left: View, Right: View>: NSViewRepresentable {
    public var left: Left
    public var right: Right

    public init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    public func makeNSView(context: Context) -> NSSplitView {
        let split = WideDividerSplitView()
        split.isVertical = true
        split.dividerStyle = .paneSplitter
        split.delegate = context.coordinator

        let leftHost = NSHostingView(rootView: left)
        let rightHost = NSHostingView(rootView: right)

        split.addSubview(leftHost)
        split.addSubview(rightHost)
        split.adjustSubviews()

        return split
    }

    public func updateNSView(_ split: NSSplitView, context: Context) {
        if let leftHost = split.subviews.first as? NSHostingView<Left> {
            leftHost.rootView = left
        }
        if split.subviews.count > 1, let rightHost = split.subviews[1] as? NSHostingView<Right> {
            rightHost.rootView = right
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, NSSplitViewDelegate {
        public func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 300
        }

        public func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.width - 300
        }
    }
}

/// NSSplitView subclass: thick divider for easy dragging, drawn as a thin line.
private final class WideDividerSplitView: NSSplitView {

    override var dividerThickness: CGFloat { 9 }

    override func drawDivider(in rect: NSRect) {
        let lineX = rect.midX - 0.5
        let lineRect = NSRect(x: lineX, y: rect.origin.y, width: 1, height: rect.height)
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard subviews.count > 1 else { return }
        let leftEnd = subviews[0].frame.maxX
        let dividerRect = NSRect(x: leftEnd, y: 0, width: dividerThickness, height: bounds.height)
        addCursorRect(dividerRect, cursor: .resizeLeftRight)
    }
}
