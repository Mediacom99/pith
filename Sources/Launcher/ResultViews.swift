import AppKit

/// One result: icon and name. Laid out with fixed frames (no Auto Layout) and reused by the table as rows change.
final class ResultCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")

    let icon = IconView()

    init() {
        // Any width: the table sizes the cell to the column and the title stretches with it.
        let width: CGFloat = 600
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.rowHeight))
        identifier = Self.identifier

        icon.frame = NSRect(
            x: 8, y: ((Layout.rowHeight - Layout.iconSize) / 2).rounded(), width: Layout.iconSize,
            height: Layout.iconSize)
        icon.autoresizingMask = [.minYMargin, .maxYMargin]

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 15)
        title.lineBreakMode = .byTruncatingTail
        let titleX = icon.frame.maxX + 10
        let titleHeight = ceil(title.intrinsicContentSize.height)
        title.frame = NSRect(
            x: titleX, y: ((Layout.rowHeight - titleHeight) / 2).rounded(), width: width - titleX - 8,
            height: titleHeight)
        title.autoresizingMask = [.width, .minYMargin, .maxYMargin]

        addSubview(icon)
        addSubview(title)
        textField = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Shows a ready-made bitmap as its layer's contents: no drawing, no scaling.
final class IconView: NSView {
    var image: CGImage? {
        didSet { if image !== oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contents = image
    }
}

/// Draws the selection in the accent color although the search field, not the table, has the focus.
final class ResultRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultRow")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}
