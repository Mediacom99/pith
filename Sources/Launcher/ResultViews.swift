import AppKit

/// One result: icon and name. Reused by the table as rows scroll.
final class ResultCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 15)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for subview in [icon, title] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Layout.iconSize),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        imageView = icon
        textField = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
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

/// App icons, loaded the first time a row shows them and kept in an `NSCache` (FEATURES.md §10).
final class IconCache {
    private let cache = NSCache<NSURL, NSImage>()

    func icon(for url: URL) -> NSImage {
        if let icon = cache.object(forKey: url as NSURL) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: Layout.iconSize, height: Layout.iconSize)
        cache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}
