import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverMonitors: [Any] = []
    private var popoverObserver: NSObjectProtocol?
    private var launchedAtLogin = false
    private var bag: Set<AnyCancellable> = []
    private let tuner = TunerModel.shared
    private let state = AppState.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Login items are launched with keyAEPropData = keyAELaunchedAsLogInItem ('prdt' = 'lgit').
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Light / dark follows the user's choice; nil = the system setting.
        Prefs.shared.$appearance.sink { mode in
            NSApp.appearance = switch mode {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }.store(in: &bag)
        Prefs.shared.$instrumentID.combineLatest(Prefs.shared.$pluckSound).sink { _ in
            DispatchQueue.main.async { SampleLibrary.shared.preload(Timbre.current().samples) }
        }.store(in: &bag)
        NSApp.mainMenu = MainMenu.build()
        // Menus follow the in-app language setting.
        Prefs.shared.$language.dropFirst().sink { _ in
            DispatchQueue.main.async { NSApp.mainMenu = MainMenu.build() }
        }.store(in: &bag)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Chorden"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.backgroundColor = Theme.windowBG
        window.minSize = NSSize(width: 620, height: 540)
        window.delegate = self
        let host = NSHostingView(rootView: MainView())
        // The window owns its size; SwiftUI's own min size (e.g. the chord chips laid out at zero width)
        // would otherwise grow the window past the screen.
        host.sizingOptions = []
        window.contentView = host
        if !window.setFrameUsingName("TonicMain") { window.center() }
        if let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame,
           !visible.contains(window.frame) {
            var f = window.frame
            f.size.width = min(f.width, visible.width)
            f.size.height = min(f.height, visible.height)
            f.origin.x = max(visible.minX, min(f.minX, visible.maxX - f.width))
            f.origin.y = max(visible.minY, min(f.minY, visible.maxY - f.height))
            window.setFrame(f, display: false)
        }
        window.setFrameAutosaveName("TonicMain")

        setUpStatusItem()

        NotificationCenter.default.addObserver(self, selector: #selector(updateListening),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        state.$tab.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateListening() }
        }.store(in: &bag)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleKey(e) == true ? nil : e
        }
        HotKey.register { [weak self] in self?.togglePopover() }

        if launchedAtLogin {
            // Started with the Mac: live in the menu bar until asked for.
            NSApp.hide(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing keeps playing once the window is gone.
        ProgressionPlayer.shared.stop()
        MetronomeModel.shared.stop()
        SingModel.shared.stop()
        EarQuizModel.shared.stop()
        DispatchQueue.main.async { self.updateListening() }
    }

    /// The window holds the mic only while the tuner tab is actually visible.
    @objc private func updateListening() {
        let visible = window.isVisible && window.occlusionState.contains(.visible) && !window.isMiniaturized
        if visible && state.tab == .tuner { tuner.acquire("window") } else { tuner.release("window") }
    }

    private func showWindow() {
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        updateListening()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.statusImage()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Dismissal is handled here (see popoverDidShow) so clicks in Chorden's dropdown panels don't close it.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        let content = NSHostingController(rootView: MiniTunerView { [weak self] in
            self?.popover.performClose(nil)
            self?.showWindow()
        })
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            menu.addItem(withTitle: tr("Open Chorden"), action: #selector(openFromMenu(_:)), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: tr("Quit Chorden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func openFromMenu(_ sender: Any?) { showWindow() }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    func popoverDidShow(_ notification: Notification) {
        tuner.acquire("popover")
        let close = { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in close() }) {
            popoverMonitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            guard let self else { return e }
            let w = e.window
            let inside = w === self.popover.contentViewController?.view.window || Dropdowns.shared.contains(w)
                || w === self.statusItem.button?.window
            if !inside { close() }
            return e
        }) { popoverMonitors.append(m) }
        popoverObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                 object: nil, queue: .main) { _ in close() }
    }

    func popoverDidClose(_ notification: Notification) {
        tuner.release("popover")
        Dropdowns.shared.closeAll()
        popoverMonitors.forEach(NSEvent.removeMonitor)
        popoverMonitors = []
        if let o = popoverObserver { NotificationCenter.default.removeObserver(o) }
        popoverObserver = nil
    }

    /// Menu bar glyph: the icon's unison ellipse (the 1:1 Lissajous figure, 135° apart), as a template image.
    private static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            for i in 0...240 {
                let t = Double(i) / 240 * 2 * .pi
                let p = NSPoint(x: 9 + 5.4 * sin(t + 3 * .pi / 4), y: 9 + 5.4 * sin(t))
                i == 0 ? path.move(to: p) : path.line(to: p)
            }
            path.close()
            path.lineWidth = 1.6
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Chorden"
        return image
    }

    // MARK: - Keys
    // Tuner: ←/→ step strings, 1–8 pick one, Esc = auto / clear marks, Space = reference tone.
    // Metronome: Space start/stop, ↑/↓ tempo (⇧ ×10), T tap.

    private func handleKey(_ e: NSEvent) -> Bool {
        let key = NSApp.keyWindow
        let inPopover = popover.isShown && key === popover.contentViewController?.view.window
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if key?.firstResponder is NSTextView { return false }
        if key === window && state.tab == .progressions {
            let prefs = Prefs.shared
            let step: Double = e.modifierFlags.contains(.shift) ? 10 : 1
            switch e.keyCode {
            case 49: ProgressionPlayer.shared.toggle()
            case 126: prefs.progressionBPM = min(220, prefs.progressionBPM + step)
            case 125: prefs.progressionBPM = max(40, prefs.progressionBPM - step)
            default: return false
            }
            return true
        }
        if key === window && state.tab == .sing {
            switch e.keyCode {
            case 49: SingModel.shared.toggle()
            case 9: Prefs.shared.singPlayVoice.toggle()
            case 46: Prefs.shared.singPlayMelody.toggle()
            default: return false
            }
            return true
        }
        if key === window && state.tab == .earquiz {
            // EarQuiz: Space plays the question again, 1–9, 0, − and = answer, Return / → next, Esc ends choosing.
            let quiz = EarQuizModel.shared
            switch e.keyCode {
            case 49: quiz.space()
            case 36, 76, 124: quiz.advance()
            case 53:
                guard quiz.editing else { return false }
                quiz.editing = false
            default:
                guard let c = e.charactersIgnoringModifiers?.first, let i = EarQuizModel.keys.firstIndex(of: c) else { return false }
                quiz.answer(index: i)
            }
            return true
        }
        if key === window && state.tab == .metronome {
            let metronome = MetronomeModel.shared
            let step: Double = e.modifierFlags.contains(.shift) ? 10 : 1
            switch e.keyCode {
            case 49: metronome.toggle()
            case 126: metronome.nudge(step)
            case 125: metronome.nudge(-step)
            case 17: metronome.tap()
            default: return false
            }
            return true
        }
        guard inPopover || (key === window && state.tab == .tuner) else { return false }
        switch e.keyCode {
        case 123: tuner.stepLock(-1)
        case 124: tuner.stepLock(1)
        case 53:
            // Esc: first release a locked string, then clear the green "tuned" marks.
            if tuner.lockedString != nil {
                tuner.lockedString = nil
            } else if !tuner.tunedStrings.isEmpty {
                tuner.clearTuned()
            } else if inPopover {
                popover.performClose(nil)
            } else {
                return false
            }
        case 49: tuner.referenceOn.toggle()
        default:
            guard let c = e.charactersIgnoringModifiers, let n = Int(c), n >= 1, n <= tuner.lockCount else { return false }
            tuner.toggleLock(n - 1)
        }
        return true
    }

    // MARK: - Menu actions

    @objc func showSettings(_ sender: Any?) {
        showWindow()
        DispatchQueue.main.async { self.state.settingsRequest += 1 }
    }

    @objc func showTuner(_ sender: Any?) {
        showWindow()
        state.tab = .tuner
    }

    @objc func showScales(_ sender: Any?) {
        showWindow()
        state.tab = .scales
    }

    @objc func showMetronome(_ sender: Any?) {
        showWindow()
        state.tab = .metronome
    }

    @objc func showProgressions(_ sender: Any?) {
        showWindow()
        state.tab = .progressions
    }

    @objc func showSing(_ sender: Any?) {
        showWindow()
        state.tab = .sing
    }

    @objc func showEarQuiz(_ sender: Any?) {
        showWindow()
        state.tab = .earquiz
    }

    @objc func toggleMetronome(_ sender: Any?) { MetronomeModel.shared.toggle() }

    @objc func showChords(_ sender: Any?) {
        showWindow()
        state.tab = .chords
    }

    @objc func findChord(_ sender: Any?) {
        showWindow()
        state.tab = .chords
        DispatchQueue.main.async { self.state.searchRequest += 1 }
    }

    @objc func toggleReference(_ sender: Any?) { tuner.referenceOn.toggle() }
}
