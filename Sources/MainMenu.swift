import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: tr(title), action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }

        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: tr(title))
            items.forEach(m.addItem)
            let holder = NSMenuItem()
            holder.submenu = m
            main.addItem(holder)
        }

        submenu("Chorden", [
            item("About Chorden", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Hide Chorden", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Chorden", #selector(NSApplication.terminate(_:)), "q"),
        ])

        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find Chord…", #selector(AppDelegate.findChord(_:)), "f"),
        ])

        submenu("View", [
            item("Tuner", #selector(AppDelegate.showTuner(_:)), "1"),
            item("Chords", #selector(AppDelegate.showChords(_:)), "2"),
            item("Progressions", #selector(AppDelegate.showProgressions(_:)), "3"),
            item("Scales", #selector(AppDelegate.showScales(_:)), "4"),
            item("Metronome", #selector(AppDelegate.showMetronome(_:)), "5"),
            item("Sing & Find", #selector(AppDelegate.showSing(_:)), "6"),
            .separator(),
            item("Reference Tone", #selector(AppDelegate.toggleReference(_:)), "r"),
            item("Start/Stop Metronome", #selector(AppDelegate.toggleMetronome(_:)), "k"),
        ])

        submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])

        return main
    }
}
