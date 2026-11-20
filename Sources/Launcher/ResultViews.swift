import AppKit

/// One row: icon and title, with a detail line under the title when there is one (a file's folder), and a dot under
/// the icon when the app is running. Laid out with fixed frames (no Auto Layout, no text measuring) and reused by
/// the table as rows change.
final class ResultCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")

    let icon = IconView()
    private let runningDot = DotView()
    private let detailLabel = NSTextField(labelWithString: "")
    private let titleHeight: CGFloat
    private let detailHeight: CGFloat

    var isRunning: Bool {
        get { !runningDot.isHidden }
        set { runningDot.isHidden = !newValue }
    }

    /// The small second line, in the secondary color, cut in the middle when it doesn't fit.
    var detail: String {
        get { detailLabel.stringValue }
        set {
            guard newValue != detailLabel.stringValue else { return }
            detailLabel.stringValue = newValue
            needsLayout = true
        }
    }

    /// Emphasized on the selected row: the labels, symbol and running dot turn white.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            detailLabel.cell?.backgroundStyle = backgroundStyle
            let selected = backgroundStyle == .emphasized
            icon.isSelected = selected
            runningDot.isSelected = selected
        }
    }

    init() {
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 15)
        // Cut in the middle, so both the start and the extension stay visible.
        title.lineBreakMode = .byTruncatingMiddle
        titleHeight = ceil(title.intrinsicContentSize.height)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailHeight = ceil(detailLabel.intrinsicContentSize.height)

        // Any width: the table sizes the cell to the column and `layout` fits the labels.
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Layout.rowHeight))
        identifier = Self.identifier

        let iconY = ((Layout.rowHeight - Layout.iconSize) / 2).rounded()
        icon.frame = NSRect(x: Layout.iconX, y: iconY, width: Layout.iconSize, height: Layout.iconSize)
        runningDot.frame = NSRect(x: icon.frame.midX - 2, y: iconY - 5, width: 4, height: 4)
        runningDot.isHidden = true

        addSubview(icon)
        addSubview(runningDot)
        addSubview(title)
        addSubview(detailLabel)
        textField = title
    }

    /// One line centered, or the title over the detail, both as wide as the row.
    override func layout() {
        super.layout()
        guard let title = textField else { return }
        // The cell spans the panel (plain table style), so these are the panel's grid.
        let x = Layout.textX
        let width = max(0, bounds.width - Layout.textTrailing - x)
        if detailLabel.stringValue.isEmpty {
            detailLabel.isHidden = true
            title.frame = NSRect(
                x: x, y: ((bounds.height - titleHeight) / 2).rounded(), width: width, height: titleHeight)
        } else {
            detailLabel.isHidden = false
            let bottom = ((bounds.height - titleHeight - detailHeight) / 2).rounded()
            detailLabel.frame = NSRect(x: x, y: bottom, width: width, height: detailHeight)
            title.frame = NSRect(x: x, y: bottom + detailHeight, width: width, height: titleHeight)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Shows a ready-made bitmap as its layer's contents: no drawing, no scaling. A symbol also comes in white, for the
/// selected row.
final class IconView: NSView {
    var image: CGImage? {
        didSet { if image !== oldValue { needsDisplay = true } }
    }
    var selectedImage: CGImage? {
        didSet { if selectedImage !== oldValue { needsDisplay = true } }
    }
    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
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
        layer?.contents = (isSelected ? selectedImage : nil) ?? image
    }
}

/// A small filled circle in the secondary label color, like the Dock's running indicator. White on the selected row.
final class DotView: NSView {
    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = bounds.width / 2
        layer?.backgroundColor =
            (isSelected ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor).cgColor
    }
}

/// Draws the selection in the accent color although the search field, not the table, has the focus: a rounded
/// rectangle inset from the panel's sides.
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

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: Layout.selectionInset, dy: 0), xRadius: Layout.selectionRadius,
            yRadius: Layout.selectionRadius
        ).fill()
    }
}
