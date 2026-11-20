import AppKit

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
// The bundle's LSUIElement already does this; this covers running the bare binary.
application.setActivationPolicy(.accessory)
application.run()
