import ServiceManagement
import SwiftUI

enum Tab: String, CaseIterable {
    case tuner, chords, progressions, scales, metronome, sing

    var title: String { self == .sing ? "Sing & Find" : rawValue.capitalized }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .tuner {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }
    /// Bumped by ⌘F to focus the chord search field.
    @Published var searchRequest = 0
    /// Bumped by ⌘, to open the settings panel.
    @Published var settingsRequest = 0
}

struct MainView: View {
    @ObservedObject var app = AppState.shared
    @ObservedObject var prefs = Prefs.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 4) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        TextChoice(title: tr(t.title), selected: app.tab == t, size: 12) { app.tab = t }
                    }
                }
                HStack(spacing: 0) {
                    Spacer()
                    // One click flips to the other look (Settings → Appearance can return to System).
                    Button { prefs.appearance = scheme == .dark ? .light : .dark } label: {
                        Image(systemName: scheme == .dark ? "sun.max" : "moon")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 30, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(scheme == .dark ? tr("Light mode") : tr("Dark mode"))
                    Dropdown(chevron: false, trigger: app.settingsRequest) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 18, height: 18)
                    } content: { SettingsView() }
                    .help(tr("Settings (⌘,)"))
                }
                .padding(.trailing, 14)
            }
            .frame(height: 38)

            switch app.tab {
            case .tuner: TunerView()
            case .chords: ChordsView()
            case .progressions: ProgressionsView()
            case .scales: ScalesView()
            case .metronome: MetronomeView()
            case .sing: SingView()
            }
        }
        .background(Theme.bg)
    }
}

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var devices = AudioInput.devices()
    @State private var loginItem = SMAppService.mainApp.status == .enabled

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
            GridRow {
                label("Language")
                HStack(spacing: 2) {
                    TextChoice(title: "English", selected: prefs.language == .en, size: 11) { prefs.language = .en }
                    TextChoice(title: "Türkçe", selected: prefs.language == .tr, size: 11) { prefs.language = .tr }
                }
            }
            GridRow {
                label("Appearance")
                HStack(spacing: 2) {
                    ForEach(AppearanceMode.allCases, id: \.self) { m in
                        TextChoice(title: tr(m.rawValue.capitalized), selected: prefs.appearance == m, size: 11) {
                            prefs.appearance = m
                        }
                    }
                }
            }
            GridRow {
                label("Guitar sound")
                HStack(spacing: 2) {
                    ForEach(PluckSound.allCases, id: \.self) { snd in
                        TextChoice(title: tr(snd.name), selected: prefs.pluckSound == snd, size: 11) {
                            prefs.pluckSound = snd
                            // Let the choice be heard: an open E-major strum.
                            Synth.shared.strum([40, 47, 52, 56, 59, 64].enumerated().map { i, m in
                                Synth.Note(frequency: Music.frequency(midi: Double(m), a4: prefs.a4), string: i)
                            })
                        }
                        .help(tr(snd.detail))
                    }
                }
            }
            GridRow {
                label("Reference")
                HStack(spacing: 4) {
                    step("minus") { prefs.a4 = max(400, prefs.a4 - 1) }
                    Text(String(format: "A4 = %g Hz", prefs.a4))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .frame(width: 92)
                        .onTapGesture(count: 2) { prefs.a4 = 440 }
                        .help(tr("Double-click to reset to 440 Hz"))
                    step("plus") { prefs.a4 = min(480, prefs.a4 + 1) }
                    ForEach([432.0, 440, 442], id: \.self) { v in
                        TextChoice(title: String(format: "%g", v), selected: prefs.a4 == v, size: 11) { prefs.a4 = v }
                    }
                }
            }
            GridRow {
                label("In tune within")
                HStack(spacing: 2) {
                    ForEach([1.0, 2, 3, 5], id: \.self) { t in
                        TextChoice(title: String(format: "±%g ¢", t), selected: prefs.tolerance == t, size: 11) {
                            prefs.tolerance = t
                        }
                    }
                }
            }
            GridRow {
                label("Note names")
                HStack(spacing: 2) {
                    TextChoice(title: "C D E", selected: prefs.notation.naming == .letters, size: 11) {
                        prefs.notation.naming = .letters
                    }
                    TextChoice(title: "Do Re Mi", selected: prefs.notation.naming == .solfege, size: 11) {
                        prefs.notation.naming = .solfege
                    }
                    Spacer().frame(width: 12)
                    TextChoice(title: "♯", selected: prefs.notation.accidental == .sharp, size: 12) {
                        prefs.notation.accidental = .sharp
                    }
                    TextChoice(title: "♭", selected: prefs.notation.accidental == .flat, size: 12) {
                        prefs.notation.accidental = .flat
                    }
                }
            }
            GridRow {
                label("Input")
                Dropdown {
                    Text(devices.first { $0.uid == prefs.inputUID }?.name ?? tr("System Default"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text)
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        DropdownItem(title: tr("System Default"), selected: prefs.inputUID == nil) {
                            prefs.inputUID = nil
                            prefs.inputChannel = 0
                        }
                        ForEach(devices) { d in
                            DropdownItem(title: d.name, detail: d.channels > 1 ? "\(d.channels) ch" : nil,
                                         selected: prefs.inputUID == d.uid) {
                                prefs.inputUID = d.uid
                                prefs.inputChannel = 0
                            }
                        }
                    }
                }
                .padding(.leading, -8)
            }
            GridRow {
                // Interfaces put each jack on its own channel; "Loudest" follows whichever is playing.
                let channels = devices.first { $0.uid == (prefs.inputUID ?? AudioInput.defaultDeviceUID()) }?.channels ?? 1
                label("Channel")
                Dropdown {
                    Text(prefs.inputChannel == 0 ? tr("Loudest") : trf("Input %d", prefs.inputChannel))
                        .font(.system(size: 12)).foregroundStyle(Theme.text)
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        DropdownItem(title: tr("Loudest"), selected: prefs.inputChannel == 0) { prefs.inputChannel = 0 }
                        ForEach(1...max(1, channels), id: \.self) { c in
                            DropdownItem(title: trf("Input %d", c), selected: prefs.inputChannel == c) { prefs.inputChannel = c }
                        }
                    }
                }
                .padding(.leading, -8)
            }
            GridRow {
                label("Noise gate")
                HStack {
                    Slider(value: $prefs.gate, in: -80...(-30)).frame(width: 160).tint(Theme.dim)
                    Text("\(Int(prefs.gate.rounded())) dB")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.dim)
                }
            }
            GridRow {
                label("Open at login")
                Toggle("", isOn: $loginItem)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .onChange(of: loginItem) { on in
                        let service = SMAppService.mainApp
                        do { if on { try service.register() } else { try service.unregister() } } catch {}
                        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                    }
            }
        }
        .padding(20)
        .onAppear { devices = AudioInput.devices() }
    }

    private func label(_ s: String) -> some View {
        Text(tr(s)).font(.system(size: 12)).foregroundStyle(Theme.dim).gridColumnAlignment(.trailing)
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.dim)
    }
}
