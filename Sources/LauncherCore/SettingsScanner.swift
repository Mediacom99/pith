import Foundation

/// A page of System Settings that the launcher lists (decision 79).
public struct SettingsPage: Sendable, Equatable {
    /// Its extension's bundle id, which opens it: `x-apple.systempreferences:<bundleID>`.
    public let bundleID: String
    /// As System Settings shows it, in the Mac's language.
    public let name: String
    /// Its extension bundle, whose icon is the page's.
    public let bundle: URL
    /// A type whose icon stands for the page instead, for a bundle without one of its own (Battery).
    public let iconType: String?

    public var item: Item { Item(settingsPage: bundleID, name: name, at: bundle) }
}

/// Reads System Settings' main pages from macOS's own list: the settings extensions, limited to the ones System
/// Settings shows in its sidebar and under General. Nothing to keep up to date: they follow the installed macOS.
public enum SettingsScanner {
    public static let extensions = URL(filePath: "/System/Library/ExtensionKit/Extensions")
    public static let settingsApp = URL(filePath: "/System/Applications/System Settings.app")

    /// Pages System Settings shows only in special cases, which Pith can't tell: follow-ups waiting, a school's Macs,
    /// an optical drive, headphones connected (named after them), a game controller used.
    static let skipped: Set<String> = [
        "com.apple.FollowUpSettings.FollowUpSettingsExtension", "com.apple.Classroom-Settings.extension",
        "com.apple.ClassKit-Settings.extension", "com.apple.CD-DVD-Settings.extension", "com.apple.HeadphoneSettings",
        "com.apple.Game-Controller-Settings.extension",
    ]
    static let extensionPoint = "com.apple.Settings.extension.ui"
    static let general = "com.apple.systempreferences.GeneralSettings"

    /// The pages, sorted by name. `hasBattery` picks between pages shown one way on a laptop and another on a desktop
    /// (Battery or Energy). `languages` are the Mac's, best first; nil asks macOS.
    public static func scan(
        extensions: URL = extensions, settingsApp: URL = settingsApp, hasBattery: Bool, languages: [String]? = nil
    ) -> [SettingsPage] {
        guard
            let bundles = try? FileManager.default.contentsOfDirectory(at: extensions, includingPropertiesForKeys: nil)
        else { return [] }
        var candidates: [(bundle: URL, info: [String: Any], id: String)] = []
        var hosted: [String] = []
        for bundle in bundles where bundle.pathExtension == "appex" {
            guard let info = plist(bundle.appending(path: "Contents/Info.plist")) as? [String: Any],
                let id = info["CFBundleIdentifier"] as? String,
                let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                attributes["EXExtensionPointIdentifier"] as? String == extensionPoint
            else { continue }
            let settings = attributes["SettingsExtensionAttributes"] as? [String: Any] ?? [:]
            if id == general { hosted = settings["hosted_bundles"] as? [String] ?? [] }
            guard settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true, !skipped.contains(id) else {
                continue
            }
            candidates.append((bundle, info, id))
        }
        // Without the sidebar's list (a macOS that moved it), every page that can be opened.
        let shown = sidebar(of: settingsApp).map { $0.union(hosted) }
        var pages: [SettingsPage] = []
        for candidate in candidates where shown?.contains(candidate.id) ?? true {
            if let page = page(candidate.bundle, info: candidate.info, id: candidate.id, hasBattery, languages) {
                pages.append(page)
            }
        }
        return pages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The bundle ids in System Settings' sidebar, from its `Sidebar*.plist`: groups of ordered and sortable ids.
    static func sidebar(of settingsApp: URL) -> Set<String>? {
        let resources = settingsApp.appending(path: "Contents/Resources")
        guard
            let file = (try? FileManager.default.contentsOfDirectory(atPath: resources.path))?
                .filter({ $0.hasPrefix("Sidebar") && $0.hasSuffix(".plist") }).max(),
            let groups = plist(resources.appending(path: file)) as? [[String: Any]]
        else { return nil }
        var ids = Set<String>()
        for group in groups {
            for key in ["ordered_content", "sortable_content"] { ids.formUnion(group[key] as? [String] ?? []) }
        }
        return ids.isEmpty ? nil : ids
    }

    private static func page(
        _ bundle: URL, info: [String: Any], id: String, _ hasBattery: Bool, _ languages: [String]?
    ) -> SettingsPage? {
        let region = developmentRegion(info)
        func localized(_ key: String, table: String) -> String? {
            Self.localized(key, table: table, in: bundle, region: region, languages: languages)
        }
        let attributes = (info["EXAppExtensionAttributes"] as? [String: Any])?["SettingsExtensionAttributes"]
        // A page with several representations shows the one whose condition holds: only the battery's is known here.
        let representations = (attributes as? [String: Any])?["representations"] as? [[String: Any]] ?? []
        let representation = representations.first { representation in
            holds(
                representation["predicate"] as? String, hidden: representation["hidden"] as? Bool == true,
                hasBattery: hasBattery)
        }
        if representation?["hidden"] as? Bool == true { return nil }
        // A sidebar name is a key in the page's strings ("BATTERY_PREF_TITLE"), or English words used as one.
        let sidebarName = representation?["sidebar-name"] as? String
        let name =
            sidebarName.flatMap { localized($0, table: "Localizable") ?? ($0.contains(" ") ? $0 : nil) }
            ?? localized("CFBundleDisplayName", table: "InfoPlist") ?? info["CFBundleDisplayName"] as? String
            ?? localized("CFBundleName", table: "InfoPlist") ?? info["CFBundleName"] as? String
        guard let name, !name.isEmpty else { return nil }
        return SettingsPage(
            bundleID: id, name: name, bundle: bundle,
            iconType: representation?["sidebar-iconUTTypeIdentifier"] as? String)
    }

    /// Whether a representation's condition holds. Only the battery's is known. Any other is taken for the usual
    /// Mac: a page that shows when something is there (`device.mouse == YES`) shows, and one hidden for a case (a
    /// guest user, no mouse) isn't.
    static func holds(_ predicate: String?, hidden: Bool, hasBattery: Bool) -> Bool {
        switch predicate?.replacingOccurrences(of: " ", with: "") {
        case "powersource.battery==YES": hasBattery
        case "powersource.battery!=YES": !hasBattery
        case let other: !hidden && !(other?.contains("!=") ?? false)
        }
    }

    /// `key` in the bundle's `<table>.loctable` (every language in one file) for the Mac's first language it has, or
    /// nil when that's the development region, whose values are in Info.plist itself.
    static func localized(_ key: String, table: String, in bundle: URL, region: String, languages: [String]?) -> String?
    {
        let file = bundle.appending(path: "Contents/Resources/\(table).loctable")
        guard let tables = plist(file) as? [String: [String: Any]] else { return nil }
        let available = Array(tables.keys) + (tables[region] == nil ? [region] : [])
        let preferred =
            languages.map { Bundle.preferredLocalizations(from: available, forPreferences: $0) }
            ?? Bundle.preferredLocalizations(from: available)
        guard let language = preferred.first else { return nil }
        return tables[language]?[key] as? String
    }

    private static func developmentRegion(_ info: [String: Any]) -> String {
        let region = info["CFBundleDevelopmentRegion"] as? String ?? "en"
        return region == "English" ? "en" : region
    }

    private static func plist(_ file: URL) -> Any? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }
}
