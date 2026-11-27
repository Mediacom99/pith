import AppKit

/// The tile under the search bar: what ⏎ acts on, large (its icon, name, where it is and what it is), and the keys
/// for ⏎ and ⌘K (decision 29). Fixed frames; it changes with the selection, and only when what it shows does.
///
/// In the clipboard it's three rows taller and becomes the preview (docs/BRIEF-CLIPBOARD.md): a text as it will paste,
/// an image in its box, a link or files as an item. Every kind reads the same way there, so nothing moves as the
/// selection goes from one to another: what it is hangs from the top, keys included, and the line about when and where
/// it was copied runs along the bottom (beside an image, which fills the height).
final class TileView: NSView {
    /// A key the tile shows: what it does, and its key caps.
    struct Key: Equatable {
        var words: String
        var caps: [String]
    }

    /// What the clipboard previews in place of the icon and name.
    enum Preview: Equatable {
        /// A text's first lines, as they'll paste. `isBlank`: only whitespace, described instead. `isRich`: rich text,
        /// in the system font, since it pastes with its own; plain text is in SF Mono, to show quotes, tabs and indents.
        case text(String, isBlank: Bool, isRich: Bool = false)
        /// An image in a box of this size in points; nil while it loads.
        case image(CGImage?, size: CGSize)
    }

    struct Content: Equatable {
        var icon: CGImage?
        var name: String
        /// Where it is: its folder, or what it is for a command.
        var place = ""
        /// What it is, and when it was last opened.
        var kind = ""
        /// What ⏎ does. Empty for no keys.
        var primary: String
        /// Force Quit waiting for its second ⏎: the primary key in red.
        var isDanger = false
        /// The other key: ⌘K for actions, ⎋ inside them.
        var secondary: Key?
        var preview: Preview? = nil
        /// How many lines `place` may wrap over (a link's URL); past them it's cut in the middle.
        var placeLines = 1
        /// Lines under `place` in the clipboard's taller tile, each cut in the middle: a copy's other files.
        var list: [String] = []
    }

    /// The most `list` lines the tile shows.
    static let listLimit = 5

    private static let padding: CGFloat = 16
    private static let iconGap: CGFloat = 14
    private static let keysGap: CGFloat = 16
    private static let lineGap: CGFloat = 1
    /// Between a text preview and the line about it.
    private static let previewGap: CGFloat = 8
    private static let placeFont = NSFont.systemFont(ofSize: 12)
    private static let plainFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let richFont = NSFont.systemFont(ofSize: 13)

    var content = Content(name: "", primary: "") {
        didSet { if content != oldValue { show(content) } }
    }

    /// The primary key's caps: `open`'s key, ↩ by default (decision 55).
    var openCaps = ["↩"] {
        didSet { if openCaps != oldValue { show(content) } }
    }

    let icon = IconView()
    private let nameLabel = TileView.label(font: .systemFont(ofSize: 19, weight: .semibold), color: .labelColor)
    let placeLabel = TileView.label(font: placeFont, color: Palette.quiet)
    /// The place label's height on one line, as its cell measures it.
    private lazy var placeLineHeight = placeLabel.frame.height
    let kindLabel = TileView.label(font: .systemFont(ofSize: 12), color: Palette.quiet)
    let listLabels = (0..<TileView.listLimit).map { _ in
        TileView.label(font: TileView.placeFont, color: Palette.quiet)
    }
    let keys = KeysView()
    /// The clipboard's previews.
    let previewText: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = plainFont
        label.textColor = .labelColor
        label.maximumNumberOfLines = ClipText.previewLines
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.isSelectable = false
        return label
    }()
    let previewImage = IconView()
    private let checker = CheckerView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Its fill and corners are layer properties: the compositor draws them, so the tile never repaints.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        previewImage.cornerRadius = 6
        for view in [icon, nameLabel, placeLabel, kindLabel, keys, previewText, checker, previewImage] + listLabels {
            addSubview(view)
        }
        _ = placeLineHeight
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
        for (index, label) in listLabels.enumerated() {
            label.stringValue = index < content.list.count ? content.list[index] : ""
        }
        keys.keys =
            content.primary.isEmpty
            ? [] : [Key(words: content.primary, caps: openCaps)] + (content.secondary.map { [$0] } ?? [])
        keys.isDanger = content.isDanger
        switch content.preview {
        case .text(let text, let isBlank, let isRich)?:
            previewText.stringValue = isBlank ? "Spaces and line breaks" : text
            previewText.textColor = isBlank ? Palette.quiet : .labelColor
            previewText.font = isBlank ? Self.placeFont : isRich ? Self.richFont : Self.plainFont
            previewImage.image = nil
        case .image(let image, _)?:
            previewImage.image = image
        case nil:
            previewImage.image = nil
        }
        needsLayout = true
    }

    /// The keys on the right, the text block between them and the icon: centered on the tile's height, or from the
    /// top in the clipboard's taller tile, with the line about it along the bottom.
    override func layout() {
        super.layout()
        let tall = bounds.height > Layout.tileHeight
        let keysSize = keys.fittingSize
        keys.frame = NSRect(
            x: bounds.width - Self.padding - keysSize.width,
            y: tall ? Self.padding : ((bounds.height - keysSize.height) / 2).rounded(), width: keysSize.width,
            height: keysSize.height)
        let right = keys.keys.isEmpty ? bounds.width - Self.padding : keys.frame.minX - Self.keysGap

        var isText = false
        var visual: CGSize? = nil
        switch content.preview {
        case .text?: isText = true
        case .image(_, let size)?: visual = size
        case nil: break
        }
        previewText.isHidden = !isText
        previewImage.isHidden = visual == nil
        checker.isHidden = visual == nil
        icon.isHidden = isText || visual != nil

        // The line about it from the tile's left edge, under the icon, where a text's is: it stays put as the
        // selection goes from one kind to another. An image fills the height, so its line stays beside it.
        kindLabel.isHidden = content.kind.isEmpty
        var bottom = bounds.height - Self.padding
        let aboutAtBottom = tall && visual == nil
        if aboutAtBottom {
            let height = kindLabel.frame.height
            kindLabel.frame = NSRect(
                x: Self.padding, y: bounds.height - Self.padding - height,
                width: max(0, bounds.width - 2 * Self.padding), height: height)
            if !kindLabel.isHidden { bottom = kindLabel.frame.minY - Self.previewGap }
        }

        if isText {
            nameLabel.isHidden = true
            placeLabel.isHidden = true
            for label in listLabels { label.isHidden = true }
            previewText.frame = NSRect(
                x: Self.padding, y: Self.padding, width: max(0, right - Self.padding),
                height: max(0, bottom - Self.padding))
            return
        }

        let x: CGFloat
        if let visual {
            let box = NSRect(origin: NSPoint(x: Self.padding, y: Self.padding), size: visual)
            previewImage.frame = box
            checker.frame = box
            x = box.maxX + Self.iconGap
        } else {
            icon.frame = NSRect(
                x: Self.padding, y: tall ? Self.padding : ((bounds.height - Layout.tileIconSize) / 2).rounded(),
                width: Layout.tileIconSize, height: Layout.tileIconSize)
            x = Self.padding + Layout.tileIconSize + Self.iconGap
        }
        let width = max(0, right - x)
        nameLabel.isHidden = false
        placeLabel.isHidden = content.place.isEmpty
        fitPlace(width: width)
        for (index, label) in listLabels.enumerated() { label.isHidden = index >= content.list.count }
        let list = listLabels.prefix(content.list.count)
        let lines = ([nameLabel, placeLabel] + list + (aboutAtBottom ? [] : [kindLabel])).filter { !$0.isHidden }
        let total = lines.map(\.frame.height).reduce(0, +) + Self.lineGap * CGFloat(max(0, lines.count - 1))
        var y = tall ? Self.padding : ((bounds.height - total) / 2).rounded()
        for line in lines {
            line.frame = NSRect(x: x, y: y, width: width, height: line.frame.height)
            y += line.frame.height + Self.lineGap
        }
        // What would run into the line about it isn't shown.
        for label in list { label.isHidden = label.frame.maxY > bottom }
    }

    /// One line cut in the middle, or for a link's URL up to `placeLines` wrapped lines, cut in the middle past them.
    private func fitPlace(width: CGFloat) {
        let lines = content.placeLines
        placeLabel.maximumNumberOfLines = lines
        placeLabel.lineBreakMode = lines > 1 ? .byCharWrapping : .byTruncatingMiddle
        guard lines > 1, width > 0 else {
            placeLabel.stringValue = content.place
            placeLabel.frame.size.height = placeLineHeight
            return
        }
        let text = content.place
        func height(_ string: String) -> CGFloat {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byCharWrapping
            return ceil(
                NSAttributedString(string: string, attributes: [.font: Self.placeFont, .paragraphStyle: style])
                    .boundingRect(
                        with: NSSize(width: width - 2 * Self.textInset, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin]
                    ).height)
        }
        let limit = height("X") * CGFloat(lines) + 1
        var fitted = text
        if height(text) > limit {
            // The most characters that fit, half from each end.
            var low = 0
            var high = text.count
            while low < high {
                let keep = (low + high + 1) / 2
                if height(Self.middle(of: text, keeping: keep)) <= limit { low = keep } else { high = keep - 1 }
            }
            fitted = Self.middle(of: text, keeping: low)
        }
        placeLabel.stringValue = fitted
        placeLabel.frame.size.height = min(height(fitted), limit)
    }

    /// How far in from each side a label draws its text (its text container's line fragment padding): what fits in
    /// a label of width w is what fits in w − 2 × this.
    static let textInset: CGFloat = 2

    /// `text` with its middle replaced by "…", keeping `count` characters.
    private static func middle(of text: String, keeping count: Int) -> String {
        guard count < text.count else { return text }
        return text.prefix((count + 1) / 2) + "…" + text.suffix(count / 2)
    }

    /// Everything it shows is loaded: the icon, or the image being previewed. For snapshots.
    var isReady: Bool {
        switch content.preview {
        case .text?: true
        case .image?: previewImage.image != nil
        case nil: icon.image != nil
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

/// Behind a copied image: a faint checkerboard of the tile's and the selection's fills, which shows through where the
/// image is transparent and is hidden where it isn't.
final class CheckerView: NSView {
    private static let square: CGFloat = 6

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Palette.selection.setFill()
        let columns = Int(ceil(bounds.width / Self.square))
        let rows = Int(ceil(bounds.height / Self.square))
        for row in 0..<rows {
            for column in 0..<columns where (row + column) % 2 == 0 {
                NSRect(
                    x: CGFloat(column) * Self.square, y: CGFloat(row) * Self.square, width: Self.square,
                    height: Self.square
                ).fill(using: .sourceOver)
            }
        }
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

    var keys: [TileView.Key] = [] {
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

    /// A key cap's glyph, in the row's ↩ color: the quiet gray was 4.1:1 on a dark cap, under AA.
    private func cap(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: Self.capFont, .foregroundColor: Palette.key])
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
