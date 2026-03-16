import SwiftUI
import AppKit

/// A thin NSSplitView wrapper with a wider invisible drag target.
struct EditorSplitView<Left: View, Right: View>: NSViewRepresentable {
    var left: Left
    var right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    func makeNSView(context: Context) -> NSSplitView {
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

    func updateNSView(_ split: NSSplitView, context: Context) {
        if let leftHost = split.subviews.first as? NSHostingView<Left> {
            leftHost.rootView = left
        }
        if split.subviews.count > 1, let rightHost = split.subviews[1] as? NSHostingView<Right> {
            rightHost.rootView = right
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 300
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.width - 300
        }
    }
}

/// NSSplitView subclass: thick divider for easy dragging, drawn as a thin line.
private final class WideDividerSplitView: NSSplitView {

    // The actual draggable width (what NSSplitView uses for hit testing)
    override var dividerThickness: CGFloat { 9 }

    // Draw only a 1px line in the center of the thick divider area
    override func drawDivider(in rect: NSRect) {
        let lineX = rect.midX - 0.5
        let lineRect = NSRect(x: lineX, y: rect.origin.y, width: 1, height: rect.height)
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }

    // Show resize cursor over the full wide divider area
    override func resetCursorRects() {
        super.resetCursorRects()
        guard subviews.count > 1 else { return }
        let leftEnd = subviews[0].frame.maxX
        let dividerRect = NSRect(x: leftEnd, y: 0, width: dividerThickness, height: bounds.height)
        addCursorRect(dividerRect, cursor: .resizeLeftRight)
    }
}
