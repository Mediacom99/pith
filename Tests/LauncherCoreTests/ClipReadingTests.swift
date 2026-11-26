import CoreGraphics
import Foundation
import ImageIO
import LauncherCore
import Testing
import UniformTypeIdentifiers

struct ClipReadingTests {
    @Test func plainTextIsText() throws {
        let content = try #require(ClipReading.content(of: [[plain("docker compose up\n")]]))
        #expect(content.kind == .text && content.text == "docker compose up\n" && content.image == nil)
        #expect(content.items == [[plain("docker compose up\n")]])
    }

    @Test func textThatIsOnlySpacesIsStillText() throws {
        #expect(ClipReading.content(of: [[plain("   \n")]])?.kind == .text)
    }

    @Test func oneURLIsALink() {
        for url in ["https://github.com/acme/site/pull/42", "  http://acme.example\n", "mailto:hello@acme.example"] {
            let content = ClipReading.content(of: [[plain(url)]])
            #expect(content?.kind == .link, "\(url)")
            #expect(content?.text == url.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for text in ["see https://acme.example", "https://", "acme.example", "file:///Users/me/notes.md", "https:acme"]
        {
            #expect(ClipReading.content(of: [[plain(text)]])?.kind == .text, "\(text)")
        }
    }

    @Test func textWithFormattingIsRichText() throws {
        let html = Representation(type: "public.html", data: Data("<b>Acme</b>".utf8))
        let content = try #require(ClipReading.content(of: [[html, plain("Acme")]]))
        #expect(content.kind == .richText && content.text == "Acme")
        #expect(content.items == [[html, plain("Acme")]], "kept in the order the app offered them")
    }

    @Test func filesWinOverTheirNameAndIcon() throws {
        let report = URL(filePath: "/Users/me/Documents/Acme/Quarterly_Budget_Review.pdf")
        let notes = URL(filePath: "/Users/me/Documents/Acme/notes.md")
        let icon = Representation(type: "public.tiff", data: try image(as: .tiff))
        let content = try #require(
            ClipReading.content(of: [
                [file(report), plain("Quarterly_Budget_Review.pdf"), icon], [file(notes), plain("notes.md")],
            ]))
        #expect(content.kind == .files)
        #expect(content.text == "\(report.path)\n\(notes.path)")
        #expect(!content.items.joined().contains(icon), "the icon isn't kept (decision 61)")
    }

    /// A folder's path keeps its "/", so the panel shows a folder without asking the disk; spaces stay as they are.
    @Test func aCopiedFolderKeepsItsSlash() throws {
        let folder = URL(filePath: "/Users/me/Documents/Acme Projects/", directoryHint: .isDirectory)
        let content = try #require(ClipReading.content(of: [[file(folder)]]))
        #expect(content.text == "/Users/me/Documents/Acme Projects/")
    }

    @Test func anImageWithoutTextIsAnImage() throws {
        let png = try image(as: .png)
        let html = Representation(type: "public.html", data: Data("<img src=chart.png>".utf8))
        let content = try #require(
            ClipReading.content(of: [[Representation(type: "public.png", data: png), html]]))
        #expect(content.kind == .image && content.text.isEmpty)
        #expect(content.image == png, "PNG is kept as it is")
        #expect(content.items == [[html]], "the image itself isn't among the items")
    }

    @Test func otherImageFormatsBecomePNG() throws {
        let content = try #require(
            ClipReading.content(of: [[Representation(type: "public.tiff", data: try image(as: .tiff))]]))
        let png = try #require(content.image)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        #expect(content.items.isEmpty)
    }

    @Test func anImageWithTextIsTextWithoutTheImage() throws {
        let tiff = Representation(type: "public.tiff", data: try image(as: .tiff))
        let rtfd = Representation(type: "com.apple.flat-rtfd", data: Data("rtfd".utf8))
        let content = try #require(ClipReading.content(of: [[rtfd, plain("Chart for Acme"), tiff]]))
        #expect(content.kind == .richText)
        #expect(content.items == [[rtfd, plain("Chart for Acme")]], "a cell's picture isn't kept (decision 61)")
    }

    /// The image is read only when there's no text and no file (decision 61); an attachment's stand-in isn't text.
    @Test func anImageIsReadOnlyWithoutTextOrFiles() {
        #expect(ClipReading.needsImage([[plain("\u{FFFC}")]]))
        let html = Representation(type: "public.html", data: Data("<img src=chart.png>".utf8))
        #expect(ClipReading.needsImage([[html]]))
        #expect(ClipReading.needsImage([[plain(" \n")]]))
        #expect(!ClipReading.needsImage([[plain("Chart for Acme")]]))
        #expect(!ClipReading.needsImage([[file(URL(filePath: "/Users/me/Documents/Acme/notes.md"))]]))
    }

    @Test func keepsOnlyTheTypesAppsPasteWith() throws {
        let content = try #require(
            ClipReading.content(of: [
                [
                    Representation(type: "com.acme.private-layers", data: Data(count: 1000)), plain("Acme"),
                    Representation(type: "org.nspasteboard.source", data: Data("com.acme.app".utf8)),
                ]
            ]))
        #expect(content.items == [[plain("Acme")]])
    }

    @Test func nothingToKeepIsNotAClip() {
        #expect(ClipReading.content(of: []) == nil)
        #expect(ClipReading.content(of: [[plain("")]]) == nil)
        #expect(
            ClipReading.content(of: [[Representation(type: "com.acme.private-layers", data: Data(count: 8))]]) == nil)
        #expect(ClipReading.content(of: [[Representation(type: "public.png", data: Data("not an image".utf8))]]) == nil)
    }

    // MARK: Helpers

    private func plain(_ text: String) -> Representation {
        Representation(type: "public.utf8-plain-text", data: Data(text.utf8))
    }

    private func file(_ url: URL) -> Representation {
        Representation(type: "public.file-url", data: url.dataRepresentation)
    }

    /// A small flat-color image in `type`'s format.
    private func image(as type: UTType) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
