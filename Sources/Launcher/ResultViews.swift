import AppKit

/// One row: icon, title, an optional detail (a file's folder) after it, and a dot under the icon when the app is
/// running. Laid out with fixed frames (no Auto Layout) and reused by the table as rows change.
final class ResultCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")

    let icon = IconView()
    private let runningDot = DotView()
    private let detailLabel = NSTextField(labelWithString: "")

    var isRunning: Bool {
        get { !runningDot.isHidden }
        set { runningDot.isHidden = !newValue }
    }

    /// Shown after the title in the secondary color, cut from the start when it doesn't fit.
    var detail: String {
        get { detailLabel.stringValue }
        set {
            guard newValue != detailLabel.stringValue else { return }
            detailLabel.stringValue = newValue
            needsLayout = true
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { detailLabel.cell?.backgroundStyle = backgroundStyle }
    }

    init() {
        // Any width: the table sizes the cell to the column and the title stretches with it.
        let width: CGFloat = 600
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.rowHeight))
        identifier = Self.identifier

        let iconY = ((Layout.rowHeight - Layout.iconSize) / 2).rounded()
        icon.frame = NSRect(x: 8, y: iconY, width: Layout.iconSize, height: Layout.iconSize)
        runningDot.frame = NSRect(x: icon.frame.midX - 2, y: iconY - 5, width: 4, height: 4)
        runningDot.isHidden = true

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 15)
        title.lineBreakMode = .byTruncatingTail
        let titleX = icon.frame.maxX + 10
        let titleHeight = ceil(title.intrinsicContentSize.height)
        title.frame = NSRect(
            x: titleX, y: ((Layout.rowHeight - titleHeight) / 2).rounded(), width: width - titleX - 8,
            height: titleHeight)
        title.autoresizingMask = [.width]

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingHead
        let detailHeight = ceil(detailLabel.intrinsicContentSize.height)
        detailLabel.frame = NSRect(
            x: 0, y: ((Layout.rowHeight - detailHeight) / 2).rounded(), width: 0, height: detailHeight)

        addSubview(icon)
        addSubview(runningDot)
        addSubview(title)
        addSubview(detailLabel)
        textField = title
    }

    /// The title takes what it needs, up to two thirds of the row; the detail gets the rest.
    override func layout() {
        super.layout()
        guard let title = textField else { return }
        let end = bounds.width - 8
        guard !detailLabel.stringValue.isEmpty else {
            title.frame.size.width = end - title.frame.minX
            detailLabel.isHidden = true
            return
        }
        let available = end - title.frame.minX
        let titleWidth = min(ceil(title.intrinsicContentSize.width), (available * 2 / 3).rounded())
        title.frame.size.width = titleWidth
        let detailX = title.frame.maxX + 10
        detailLabel.frame.origin.x = detailX
        detailLabel.frame.size.width = max(0, end - detailX)
        detailLabel.isHidden = false
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

/// A small filled circle in the secondary label color, like the Dock's running indicator.
final class DotView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = bounds.width / 2
        layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
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
