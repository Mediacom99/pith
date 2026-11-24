import Foundation
import Testing

@testable import Launcher

/// Quick Look shows the file it was opened on, and follows only the user's moves.
struct PreviewTargetTests {
    let report = URL(filePath: "/Users/me/Documents/Acme/Quarterly_Budget_Review.pdf")
    let notes = URL(filePath: "/Users/me/Documents/Acme/notes.md")

    @Test func followsTheUserAndNothingElse() {
        #expect(PreviewTarget.change(showing: nil, selected: report, byUser: true) == .keep, "closed stays closed")
        #expect(PreviewTarget.change(showing: report, selected: report, byUser: false) == .keep)
        #expect(
            PreviewTarget.change(showing: report, selected: notes, byUser: true) == .show(notes), "↓, a click, typing")
        #expect(PreviewTarget.change(showing: report, selected: nil, byUser: true) == .close, "an app has no preview")
        #expect(
            PreviewTarget.change(showing: report, selected: notes, byUser: false) == .close,
            "a refresh that moved the selection closes it, rather than show a file nobody chose")
    }
}
