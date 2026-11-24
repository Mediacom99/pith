import CoreGraphics

/// Panel geometry. Visual decisions, recorded in docs/ARCHITECTURE.md (decision 29).
enum Layout {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 52
    static let cornerRadius: CGFloat = 14
    /// The tile under the bar, which shows what ⏎ acts on: its height, its margin on every side, its corners and icon.
    static let tileHeight: CGFloat = 92
    static let tileMargin: CGFloat = 8
    static let tileRadius: CGFloat = 10
    static let tileIconSize: CGFloat = 48
    static let rowHeight: CGFloat = 32
    static let visibleRows: CGFloat = 8
    /// Under the last row.
    static let listBottomInset: CGFloat = 6
    /// Where the list starts: under the bar, its separator and the tile.
    static let listTop = barHeight + 1 + tileMargin * 2 + tileHeight
    static let expandedHeight = listTop + visibleRows * rowHeight + listBottomInset
    /// In the clipboard the tile is the preview: three rows taller, so five whole rows fit under it and the panel keeps
    /// its height (docs/BRIEF-CLIPBOARD.md).
    static let clipboardTileHeight = tileHeight + 3 * rowHeight
    static let clipboardListTop = listTop + 3 * rowHeight
    static let iconSize: CGFloat = 20
    /// The selection's distance from the panel's sides (the tile's margin, so the two line up), and its corners.
    static let selectionInset: CGFloat = tileMargin
    static let selectionRadius: CGFloat = 7
    /// One grid for the bar and the rows: icons start 10 pt inside the selection, and the magnifier is centered on
    /// the same column. Titles and the query start 10 pt after the icons and stop 10 pt inside the selection.
    static let iconX: CGFloat = selectionInset + 10
    static let textX: CGFloat = iconX + iconSize + 10
    static let textTrailing: CGFloat = selectionInset + 10
}
