import AppKit

/// One row, on one line: icon, name, and for files and folders their folder after the name, in the quiet color; at the
/// end a tag ("running" after a running app, a clip's age, a pin before it) and ↩ on the selected row. Laid out with
/// fixed frames and reused by the table as rows change. The name and folder are measured when they change, so the
/// folder can follow the name; both are cut in the middle when they don't fit, except a clip's text, cut at the end.
final class ResultCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")

    private static let titleFont = NSFont.systemFont(ofSize: 14)
    private static let detailFont = NSFont.systemFont(ofSize: 12)
    private static let tagFont = NSFont.systemFont(ofSize: 11)
    private static let markFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    /// Between the name and its folder, and between the trailing labels.
    private static let gap: CGFloat = 6
    /// The most of the row a folder takes from a name too long for both.
    private static let detailShare: CGFloat = 0.38

    let icon = IconView()
    private let detailLabel = ResultCell.label(font: detailFont, color: Palette.quiet)
    private let tagLabel = ResultCell.label(font: tagFont, color: Palette.quiet)
    private let pin: NSImageView = {
        let pin = NSImageView()
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pin.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        pin.contentTintColor = Palette.quiet
        pin.frame.size = pin.image?.size ?? .zero
        return pin
    }()
    private let mark = ResultCell.label("↩", font: markFont, color: Palette.key)
    private var titleWidth: CGFloat = 0
    private var detailWidth: CGFloat = 0

    var title: String {
        get { textField?.stringValue ?? "" }
        set {
            guard let title = textField, newValue != title.stringValue else { return }
            title.stringValue = newValue
            titleWidth = ceil(title.cell?.cellSize.width ?? 0)
            needsLayout = true
        }
    }

    /// The folder, after the name.
    var detail: String {
        get { detailLabel.stringValue }
        set {
            guard newValue != detailLabel.stringValue else { return }
            detailLabel.stringValue = newValue
            detailWidth = newValue.isEmpty ? 0 : ceil(detailLabel.cell?.cellSize.width ?? 0)
            needsLayout = true
        }
    }

    /// At the end of the row: "running", or a clip's age. Empty for none.
    var trailingTag: String {
        get { tagLabel.stringValue }
        set {
            guard newValue != tagLabel.stringValue else { return }
            tagLabel.stringValue = newValue
            needsLayout = true
        }
    }

    /// A pinned clip: the pin before its age.
    var isPinned = false {
        didSet { if isPinned != oldValue { needsLayout = true } }
    }

    /// A clip's text is cut at its end, where names are cut in the middle.
    var cutsAtTheEnd = false {
        didSet {
            if cutsAtTheEnd != oldValue {
                textField?.lineBreakMode = cutsAtTheEnd ? .byTruncatingTail : .byTruncatingMiddle
            }
        }
    }

    /// The title in the quiet color: text that is only spaces and line breaks, described instead of shown.
    var isQuietTitle = false {
        didSet { if isQuietTitle != oldValue { updateTitleColor() } }
    }

    /// What the selected row ends in: `open`'s key, ↩ by default (decision 55).
    var openKey = "↩" {
        didSet {
            guard openKey != oldValue else { return }
            mark.stringValue = openKey
            needsLayout = true
        }
    }

    /// Set by the row view: the selected row ends in ↩.
    var isSelected = false {
        didSet { if isSelected != oldValue { needsLayout = true } }
    }

    /// Force Quit waiting for its second ⏎: the name in red, and the row view fills it in faint red.
    var isDanger = false {
        didSet {
            guard isDanger != oldValue else { return }
            updateTitleColor()
            mark.textColor = isDanger ? Palette.danger : Palette.key
            superview?.needsDisplay = true
        }
    }

    private func updateTitleColor() {
        textField?.textColor = isDanger ? Palette.danger : isQuietTitle ? Palette.quiet : .labelColor
    }

    init() {
        let title = Self.label(font: Self.titleFont, color: .labelColor)
        // Any width: the table sizes the cell to the column and `layout` fits the labels.
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Layout.rowHeight))
        identifier = Self.identifier
        icon.frame = NSRect(
            x: Layout.iconX, y: ((Layout.rowHeight - Layout.iconSize) / 2).rounded(), width: Layout.iconSize,
            height: Layout.iconSize)
        for view in [icon, title, detailLabel, tagLabel, pin, mark] { addSubview(view) }
        tagLabel.isHidden = true
        pin.isHidden = true
        mark.isHidden = true
        textField = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private static func label(_ text: String = "", font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.frame.size = label.cell?.cellSize ?? .zero
        return label
    }

    /// The name, then the folder, then from the right ↩, the tag and the pin, every label on the name's baseline.
    override func layout() {
        super.layout()
        guard let title = textField else { return }
        let height = title.frame.height
        let titleY = ((bounds.height - height) / 2).rounded()
        let baseline = titleY + height - Self.titleFont.ascender
        func place(_ label: NSTextField, x: CGFloat, width: CGFloat, font: NSFont) {
            let height = label.frame.height
            label.frame = NSRect(x: x, y: (baseline - height + font.ascender).rounded(), width: width, height: height)
        }

        var trailing = bounds.width - Layout.textTrailing
        mark.isHidden = !isSelected
        if isSelected {
            let width = mark.cell?.cellSize.width ?? 0
            trailing -= width
            place(mark, x: trailing, width: width, font: Self.markFont)
            trailing -= Self.gap * 2
        }
        tagLabel.isHidden = trailingTag.isEmpty
        if !trailingTag.isEmpty {
            let width = ceil(tagLabel.cell?.cellSize.width ?? 0)
            trailing -= width
            place(tagLabel, x: trailing, width: width, font: Self.tagFont)
            trailing -= isPinned ? 4 : Self.gap
        }
        pin.isHidden = !isPinned
        if isPinned {
            // Centered on the tag's x-height, which reads as on its line (the cell isn't flipped: up is +y).
            let size = pin.frame.size
            trailing -= size.width
            let middle = baseline + Self.tagFont.xHeight / 2
            pin.frame.origin = NSPoint(x: trailing, y: (middle - size.height / 2).rounded())
            trailing -= Self.gap
        }
        if !trailingTag.isEmpty || isPinned { trailing -= Self.gap }

        let available = max(0, trailing - Layout.textX)
        detailLabel.isHidden = detail.isEmpty
        if detail.isEmpty {
            title.frame = NSRect(x: Layout.textX, y: titleY, width: min(titleWidth, available), height: height)
        } else {
            let room = available - Self.gap
            let titleRoom = min(titleWidth, max(room - detailWidth, room * (1 - Self.detailShare)))
            title.frame = NSRect(x: Layout.textX, y: titleY, width: titleRoom, height: height)
            place(
                detailLabel, x: Layout.textX + titleRoom + Self.gap, width: max(0, min(detailWidth, room - titleRoom)),
                font: Self.detailFont)
        }
    }
}

/// Shows a ready-made bitmap as its layer's contents: no drawing, no scaling. Rounded for a copied image's thumbnail.
final class IconView: NSView {
    var image: CGImage? {
        didSet { if image !== oldValue { needsDisplay = true } }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { if cornerRadius != oldValue { needsDisplay = true } }
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
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = cornerRadius > 0
    }
}

/// Draws the selection although the search field, not the table, has the focus: a quiet rounded rectangle inset from
/// the panel's sides, faint red while Force Quit waits for its second ⏎. Its cell shows ↩ (decision 29).
final class ResultRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultRow")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Never emphasized, so the cell keeps its colors on the selection.
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override var isSelected: Bool {
        didSet { cell?.isSelected = isSelected }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? ResultCell)?.isSelected = isSelected
    }

    /// Its cell, among its subviews: `view(atColumn:)` asserts while the table is still setting the row view up.
    private var cell: ResultCell? { subviews.lazy.compactMap { $0 as? ResultCell }.first }

    override func drawSelection(in dirtyRect: NSRect) {
        (cell?.isDanger == true ? Palette.dangerFill : Palette.selection).setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: Layout.selectionInset, dy: 0), xRadius: Layout.selectionRadius,
            yRadius: Layout.selectionRadius
        ).fill()
    }
}

/// Overlay scrollers whatever System Settings says: an always-visible scroller would take 15 pt off the rows, so a
/// list that scrolls would be narrower than one that doesn't.
final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}
