import Foundation
import LauncherCore
import TestSupport
import Testing

/// System Settings' pages (decision 79), read from made-up extensions in a temporary folder.
struct SettingsScannerTests {
    /// A settings extension: its Info.plist, and its names by language when given.
    private func page(
        _ id: String, in folder: borrowing TemporaryDirectory, file: String? = nil, name: String? = nil,
        point: String = "com.apple.Settings.extension.ui", opens: Bool = true, settings: [String: Any] = [:],
        names: [String: String] = [:], strings: [String: [String: String]] = [:]
    ) throws {
        let contents = folder.url.appending(path: "Extensions/\(file ?? id).appex/Contents")
        try FileManager.default.createDirectory(
            at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
        var attributes = settings
        attributes["allowsXAppleSystemPreferencesURLScheme"] = opens
        var info: [String: Any] = [
            "CFBundleIdentifier": id, "CFBundleDevelopmentRegion": "en",
            "EXAppExtensionAttributes": [
                "EXExtensionPointIdentifier": point, "SettingsExtensionAttributes": attributes,
            ],
        ]
        if let name { info["CFBundleDisplayName"] = name }
        try write(info, to: contents.appending(path: "Info.plist"))
        if !names.isEmpty {
            try write(
                names.mapValues { ["CFBundleDisplayName": $0] },
                to: contents.appending(path: "Resources/InfoPlist.loctable"))
        }
        if !strings.isEmpty { try write(strings, to: contents.appending(path: "Resources/Localizable.loctable")) }
    }

    private func sidebar(_ ids: [String], in folder: borrowing TemporaryDirectory) throws {
        try folder.makeFolder("System Settings.app/Contents/Resources")
        try write(
            [["ordered_content": Array(ids.prefix(1))], ["sortable_content": Array(ids.dropFirst())]],
            to: folder.url.appending(path: "System Settings.app/Contents/Resources/Sidebar124.plist"))
    }

    private func write(_ plist: Any, to file: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: file)
    }

    private func scan(
        _ folder: borrowing TemporaryDirectory, hasBattery: Bool = true, languages: [String] = ["en"]
    ) -> [SettingsPage] {
        SettingsScanner.scan(
            extensions: folder.url.appending(path: "Extensions"),
            settingsApp: folder.url.appending(path: "System Settings.app"), hasBattery: hasBattery,
            languages: languages)
    }

    /// The pages System Settings shows, in its sidebar or under General, that a link can open: not other
    /// extensions, nor pages it shows only in special cases.
    @Test func listsThePagesSystemSettingsShows() throws {
        let folder = try TemporaryDirectory()
        try page("com.acme.wifi", in: folder, name: "Wi-Fi")
        try page(
            "com.apple.systempreferences.GeneralSettings", in: folder, name: "General",
            settings: ["hosted_bundles": ["com.acme.storage"]])
        try page("com.acme.storage", in: folder, name: "Storage")
        try page("com.acme.hidden", in: folder, name: "Not in the sidebar")
        try page("com.acme.nolink", in: folder, name: "No link", opens: false)
        try page("com.acme.widget", in: folder, name: "A widget", point: "com.apple.widgetkit-extension")
        try page("com.apple.HeadphoneSettings", in: folder, name: "HeadphoneSettingsExtension")
        try sidebar(
            [
                "com.apple.systempreferences.GeneralSettings", "com.acme.wifi", "com.acme.nolink", "com.acme.widget",
                "com.apple.HeadphoneSettings", "com.acme.gone",
            ], in: folder)

        let pages = scan(folder)
        #expect(pages.map(\.name) == ["General", "Storage", "Wi-Fi"], "sorted by name")
        #expect(
            pages.first?.item.settingsURL?.absoluteString
                == "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings")
        #expect(pages.first?.item.id == "settings:com.apple.systempreferences.GeneralSettings")
    }

    /// Without System Settings' sidebar list, every page a link can open.
    @Test func withoutTheSidebarEveryPageThatOpens() throws {
        let folder = try TemporaryDirectory()
        try page("com.acme.wifi", in: folder, name: "Wi-Fi")
        try page("com.acme.nolink", in: folder, name: "No link", opens: false)
        #expect(scan(folder).map(\.name) == ["Wi-Fi"])
    }

    /// The name in the Mac's language; in the development region's, Info.plist's own. A page whose name comes from
    /// its representation (Battery, or Energy without a battery) takes it, with its icon's type.
    @Test func namesFollowTheMacsLanguageAndTheBattery() throws {
        let folder = try TemporaryDirectory()
        try page(
            "com.acme.wifi", in: folder, name: "WiFiSettings", names: ["en": "Wi‑Fi", "it": "Wi‑Fi (it)"])
        try page("com.acme.bluetooth", in: folder, name: "Bluetooth", names: ["it": "Bluetooth (it)"])
        try page(
            "com.acme.battery", in: folder, file: "PowerPreferences", name: "PowerPreferences",
            settings: [
                "representations": [
                    [
                        "predicate": "powersource.battery != YES", "sidebar-name": "ENERGY",
                        "sidebar-iconUTTypeIdentifier": "com.acme.energy",
                    ],
                    [
                        "predicate": "powersource.battery == YES", "sidebar-name": "BATTERY",
                        "sidebar-iconUTTypeIdentifier": "com.acme.battery",
                    ],
                ]
            ],
            strings: ["en": ["BATTERY": "Battery", "ENERGY": "Energy"], "it": ["BATTERY": "Batteria"]])
        try page(
            "com.acme.mouse", in: folder, name: "Mouse",
            settings: [
                "representations": [
                    ["predicate": "device.mouse == YES"], ["predicate": "device.mouse != YES", "hidden": true],
                ]
            ])
        try page(
            "com.acme.touchid", in: folder, name: "Touch ID",
            settings: [
                "representations": [
                    ["predicate": "user.isguest == YES", "hidden": true],
                    ["predicate": "device.touchID != YES", "sidebar-name": "Login Password"],
                    ["predicate": "device.touchID == YES", "sidebar-name": "Touch ID & Password"],
                ]
            ])
        try sidebar(
            ["com.acme.wifi", "com.acme.bluetooth", "com.acme.battery", "com.acme.mouse", "com.acme.touchid"],
            in: folder)

        let english = scan(folder)
        #expect(english.map(\.name) == ["Battery", "Bluetooth", "Mouse", "Touch ID & Password", "Wi‑Fi"])
        #expect(english.first?.iconType == "com.acme.battery")
        #expect(english.first?.bundle.lastPathComponent == "PowerPreferences.appex")
        #expect(
            scan(folder, languages: ["it"]).map(\.name) == [
                "Batteria", "Bluetooth (it)", "Mouse", "Touch ID & Password", "Wi‑Fi (it)",
            ])
        let desktop = scan(folder, hasBattery: false)
        #expect(desktop.first?.name == "Bluetooth")
        #expect(desktop.first { $0.bundleID == "com.acme.battery" }?.iconType == "com.acme.energy")
        #expect(desktop.map(\.name).contains("Energy"))
    }

    /// The Mac's own pages: the main ones are there, each with a name.
    @Test func readsThisMacsPages() {
        let pages = SettingsScanner.scan(hasBattery: true)
        let ids = Set(pages.map(\.bundleID))
        #expect(ids.isSuperset(of: ["com.apple.wifi-settings-extension", "com.apple.BluetoothSettings"]))
        #expect(pages.allSatisfy { !$0.name.isEmpty && !$0.name.hasSuffix("Extension") })
        #expect(ids.contains("com.apple.Touch-ID-Settings.extension"), "hidden only for a guest")
    }
}
