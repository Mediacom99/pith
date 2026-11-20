import AppKit

/// One row, on one line: icon, name, and for files and folders their folder after the name, in the quiet color;
/// "running" after a running app, and ↩ at the end of the selected row. Laid out with fixed frames and reused by the
/// table as rows change. The name and folder are measured when they change, so the folder can follow the name; both
/// are cut in the middle when they don't fit.
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
    private let tagLabel = ResultCell.label("running", font: tagFont, color: Palette.quiet)
    private let mark = ResultCell.label("↩", font: markFont, color: .secondaryLabelColor)
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

    var isRunning = false {
        didSet { if isRunning != oldValue { needsLayout = true } }
    }

    /// Set by the row view: the selected row ends in ↩.
    var isSelected = false {
        didSet { if isSelected != oldValue { needsLayout = true } }
    }

    /// Force Quit waiting for its second ⏎: the name in red, and the row view fills it in faint red.
    var isDanger = false {
        didSet {
            guard isDanger != oldValue else { return }
            textField?.textColor = isDanger ? Palette.danger : .labelColor
            mark.textColor = isDanger ? Palette.danger : .secondaryLabelColor
            superview?.needsDisplay = true
        }
    }

    init() {
        let title = Self.label(font: Self.titleFont, color: .labelColor)
        // Any width: the table sizes the cell to the column and `layout` fits the labels.
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Layout.rowHeight))
        identifier = Self.identifier
        icon.frame = NSRect(
            x: Layout.iconX, y: ((Layout.rowHeight - Layout.iconSize) / 2).rounded(), width: Layout.iconSize,
            height: Layout.iconSize)
        for view in [icon, title, detailLabel, tagLabel, mark] { addSubview(view) }
        tagLabel.isHidden = true
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

    /// The name, then the folder, then from the right ↩ and "running", every label on the name's baseline.
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
        tagLabel.isHidden = !isRunning
        if isRunning {
            let width = tagLabel.cell?.cellSize.width ?? 0
            trailing -= width
            place(tagLabel, x: trailing, width: width, font: Self.tagFont)
            trailing -= Self.gap * 2
        }

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

/// The tile under the search bar: what ⏎ acts on, large (its icon, name, where it is and what it is), and the keys
/// for ⏎ and ⌘K (decision 29). Fixed frames; it changes with the selection, and only when what it shows does.
final class StageView: NSView {
    /// A key the tile shows: what it does, and its key caps.
    struct Key: Equatable {
        var words: String
        var caps: [String]
    }

    struct Content: Equatable {
        var icon: CGImage?
        var name: String
        /// Where it is: its folder, or what it is for a command.
        var place = ""
        /// What it is, and when it was last opened.
        var kind = ""
        /// What ⏎ does.
        var primary: String
        /// Force Quit waiting for its second ⏎: the primary key in red.
        var isDanger = false
        /// The other key: ⌘K for actions, ⎋ inside them.
        var secondary: Key?
    }

    private static let padding: CGFloat = 16
    private static let iconGap: CGFloat = 14
    private static let keysGap: CGFloat = 16
    private static let lineGap: CGFloat = 1

    var content = Content(name: "", primary: "") {
        didSet { if content != oldValue { show(content) } }
    }

    let icon = IconView()
    private let nameLabel = StageView.label(font: .systemFont(ofSize: 19, weight: .semibold), color: .labelColor)
    private let placeLabel = StageView.label(font: .systemFont(ofSize: 12), color: Palette.quiet)
    private let kindLabel = StageView.label(font: .systemFont(ofSize: 12), color: Palette.quiet)
    let keys = KeysView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Its fill and corners are layer properties: the compositor draws them, so the tile never repaints.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        icon.frame = NSRect(
            x: Self.padding, y: ((frame.height - Layout.tileIconSize) / 2).rounded(), width: Layout.tileIconSize,
            height: Layout.tileIconSize)
        for view in [icon, nameLabel, placeLabel, kindLabel, keys] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private static func label(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.frame.size.height = ceil(label.cell?.cellSize.height ?? 0)
        return label
    }

    private func show(_ content: Content) {
        icon.image = content.icon
        nameLabel.stringValue = content.name
        placeLabel.stringValue = content.place
        kindLabel.stringValue = content.kind
        keys.keys = [Key(words: content.primary, caps: ["↩"])] + (content.secondary.map { [$0] } ?? [])
        keys.isDanger = content.isDanger
        needsLayout = true
    }

    /// The keys on the right, the text block between them and the icon, centered on the tile's height.
    override func layout() {
        super.layout()
        let keysSize = keys.fittingSize
        keys.frame = NSRect(
            x: bounds.width - Self.padding - keysSize.width, y: ((bounds.height - keysSize.height) / 2).rounded(),
            width: keysSize.width, height: keysSize.height)
        let x = Self.padding + Layout.tileIconSize + Self.iconGap
        let width = max(0, keys.frame.minX - Self.keysGap - x)
        let lines = [nameLabel, placeLabel, kindLabel].filter { !$0.stringValue.isEmpty }
        placeLabel.isHidden = content.place.isEmpty
        kindLabel.isHidden = content.kind.isEmpty
        let total = lines.map(\.frame.height).reduce(0, +) + Self.lineGap * CGFloat(max(0, lines.count - 1))
        var y = ((bounds.height - total) / 2).rounded()
        for line in lines {
            line.frame = NSRect(x: x, y: y, width: width, height: line.frame.height)
            y += line.frame.height + Self.lineGap
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.tile.cgColor
        layer?.cornerRadius = Layout.tileRadius
        layer?.cornerCurve = .continuous
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The tile's keys, one per line and right-aligned: words, then key caps. The first is what ⏎ does, in bold.
final class KeysView: NSView {
    private static let capSize: CGFloat = 20
    private static let capRadius: CGFloat = 5
    private static let capGap: CGFloat = 4
    private static let wordsGap: CGFloat = 8
    private static let lineGap: CGFloat = 8
    private static let capFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    var keys: [StageView.Key] = [] {
        didSet { if keys != oldValue { needsDisplay = true } }
    }

    /// The primary key in red: Force Quit waiting for its second ⏎.
    var isDanger = false {
        didSet { if isDanger != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let widths = keys.indices.map { width(of: $0) }
        let count = CGFloat(keys.count)
        return NSSize(
            width: ceil(widths.max() ?? 0), height: count * Self.capSize + max(0, count - 1) * Self.lineGap)
    }

    private func words(_ index: Int) -> NSAttributedString {
        let primary = index == 0
        return NSAttributedString(
            string: keys[index].words,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: primary ? .semibold : .regular),
                .foregroundColor: primary ? (isDanger ? Palette.danger : NSColor.labelColor) : Palette.quiet,
            ])
    }

    private func cap(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: Self.capFont, .foregroundColor: Palette.quiet])
    }

    private func capWidth(_ text: String) -> CGFloat {
        max(Self.capSize, ceil(cap(text).size().width) + 10)
    }

    private func width(of index: Int) -> CGFloat {
        let caps = keys[index].caps
        return ceil(words(index).size().width) + Self.wordsGap + caps.map(capWidth).reduce(0, +)
            + Self.capGap * CGFloat(max(0, caps.count - 1))
    }

    override func draw(_ dirtyRect: NSRect) {
        for index in keys.indices {
            let top = CGFloat(index) * (Self.capSize + Self.lineGap)
            var x = bounds.width
            for text in keys[index].caps.reversed() {
                let width = capWidth(text)
                x -= width
                let box = NSRect(x: x, y: top, width: width, height: Self.capSize)
                Palette.selection.setFill()
                NSBezierPath(roundedRect: box, xRadius: Self.capRadius, yRadius: Self.capRadius).fill()
                let glyph = cap(text)
                let size = glyph.size()
                glyph.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
                x -= Self.capGap
            }
            let words = words(index)
            let size = words.size()
            words.draw(
                at: NSPoint(x: x + Self.capGap - Self.wordsGap - size.width, y: top + (Self.capSize - size.height) / 2))
        }
    }
}
