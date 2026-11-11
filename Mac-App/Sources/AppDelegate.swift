import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let abgleich = Abgleich()
    private var timer: Timer?
    private var letzteSignatur = ""
    private var geplant: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        abgleich.onChange = { [weak self] in
            DispatchQueue.main.async { self?.symbol() }
        }
        abgleich.passwort = Keychain.read()
        symbol()

        letzteSignatur = abgleich.signatur()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }

        if abgleich.passwort == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.passwortFragen() }
        } else {
            abgleich.starten()
        }
    }

    /// Alle 5 Sekunden: Hat das Spiel gespeichert? Sonst alle 10 Minuten nach Neuem auf der Webseite sehen.
    private func tick() {
        let s = abgleich.signatur()
        if s != letzteSignatur {
            letzteSignatur = s
            geplant?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.abgleich.starten() }
            geplant = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w) // kurz warten, bis die Datei fertig geschrieben ist
        } else if Date().timeIntervalSince(abgleich.letzterStart) > 600 {
            abgleich.starten()
        }
    }

    private func symbol() {
        guard let button = item.button else { return }
        let name = abgleich.laeuft ? "arrow.triangle.2.circlepath" : (abgleich.hatProblem ? "exclamationmark.triangle" : "moon.stars.fill")
        if let bild = NSImage(systemSymbolName: name, accessibilityDescription: "Elternabend Abgleich") {
            bild.isTemplate = true
            button.image = bild
            button.title = ""
        } else {
            button.image = nil
            button.title = "🌙"
        }
        button.toolTip = "Elternabend Abgleich – " + abgleich.ueberblick()
    }

    // MARK: Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        func info(_ titel: String) {
            let i = NSMenuItem(title: titel, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        func knopf(_ titel: String, _ aktion: Selector, an: Bool = false) {
            let i = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
            i.target = self
            i.state = an ? .on : .off
            menu.addItem(i)
        }

        info("Elternabend Abgleich " + appVersion)
        info(abgleich.ueberblick())
        menu.addItem(.separator())
        for zeile in abgleich.zeilen() { info(zeile) }
        menu.addItem(.separator())
        knopf("Jetzt abgleichen", #selector(jetzt))
        knopf(abgleich.passwort == nil ? "Offizierspasswort eingeben …" : "Offizierspasswort ändern …", #selector(passwortMenue))
        knopf("WoW-Ordner: " + (abgleich.wowOrdner?.path ?? "nicht gefunden – wählen …"), #selector(ordnerWaehlen))
        knopf("Beim Anmelden am Mac starten", #selector(autostart), an: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        knopf("gilde-elternabend.de öffnen", #selector(webseite))
        knopf("Beenden", #selector(beenden))
    }

    @objc private func jetzt() {
        abgleich.starten()
    }

    @objc private func passwortMenue() {
        passwortFragen()
    }

    private func passwortFragen() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Offizierspasswort"
        a.informativeText = "Das Passwort, mit dem die Gildenleitung auf gilde-elternabend.de Listen einfügt. "
            + "Es wird im Schlüsselbund deines Macs gespeichert und nur an gilde-elternabend.de geschickt."
        let feld = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        a.accessoryView = feld
        a.addButton(withTitle: "Speichern")
        a.addButton(withTitle: "Abbrechen")
        a.window.initialFirstResponder = feld
        if a.runModal() == .alertFirstButtonReturn {
            let pw = feld.stringValue
            if !pw.isEmpty {
                Keychain.save(pw)
                abgleich.neuesPasswort(pw)
            }
        }
    }

    @objc private func ordnerWaehlen() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.message = "Wähle den Ordner „World of Warcraft“ (darin liegen Ordner wie _classic_ oder _retail_)."
        p.prompt = "Auswählen"
        p.directoryURL = abgleich.wowOrdner
        if p.runModal() == .OK, let url = p.url {
            abgleich.setzeOrdner(url)
            if abgleich.installationen().isEmpty {
                hinweis("Hier habe ich das Addon nicht gefunden",
                        "In diesem Ordner liegt kein WoW mit dem Addon Elternabend. Bitte den Ordner „World of Warcraft“ wählen.")
            }
            letzteSignatur = abgleich.signatur()
            abgleich.starten()
        }
    }

    @objc private func autostart() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            hinweis("Das hat nicht geklappt",
                    error.localizedDescription + "\n\nLiegt die App im Ordner „Programme“? Von dort aus funktioniert der Autostart.")
        }
    }

    @objc private func webseite() {
        if let url = URL(string: WebClient.basis) { NSWorkspace.shared.open(url) }
    }

    @objc private func beenden() {
        NSApp.terminate(nil)
    }

    private func hinweis(_ titel: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = titel
        a.informativeText = text
        a.runModal()
    }
}
