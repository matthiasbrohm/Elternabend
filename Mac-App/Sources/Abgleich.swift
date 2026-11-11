import CryptoKit
import Foundation

/// Ein WoW-Ordner mit Addon und/oder gespeicherten Daten (z. B. „_classic_“)
struct Installation {
    let name: String
    let saved: [URL]   // …/WTF/Account/<Konto>/SavedVariables/Elternabend.lua
    let addon: URL?    // …/Interface/AddOns/Elternabend
}

private enum Ergebnis {
    case ok
    case passwort            // Offizierspasswort falsch
    case gesperrt            // Webseite hat nach Fehlversuchen gesperrt
    case abgelehnt(String)   // Webseite hat geantwortet, aber nicht übernommen
    case netz(String)        // Webseite nicht erreichbar
}

final class Abgleich {
    struct Teil {
        let key: String
        let titel: String
    }
    /// Was das Addon für die Webseite bereitlegt (Schlüssel in der Tabelle „ElternabendSync“)
    static let teile = [
        Teil(key: "mitglieder", titel: "Klassenliste"),
        Teil(key: "pinnwand", titel: "Pinnwand"),
        Teil(key: "berufe", titel: "Berufe"),
        Teil(key: "bericht", titel: "Raid-Bericht"),
    ]

    private let d = UserDefaults.standard
    private let web = WebClient()
    private let queue = DispatchQueue(label: "de.gilde-elternabend.abgleich.lauf")
    private let lock = NSLock()
    private var _passwort: String?
    private var _laeuft = false
    private(set) var letzterStart = Date.distantPast
    var onChange: (() -> Void)?

    var passwort: String? {
        get { lock.lock(); defer { lock.unlock() }; return _passwort }
        set { lock.lock(); _passwort = newValue; lock.unlock() }
    }
    var laeuft: Bool {
        lock.lock(); defer { lock.unlock() }
        return _laeuft
    }

    // MARK: WoW-Ordner

    var wowOrdner: URL? {
        let fm = FileManager.default
        if let p = d.string(forKey: "wowOrdner"), fm.fileExists(atPath: p) { return URL(fileURLWithPath: p, isDirectory: true) }
        let ueblich = ["/Applications/World of Warcraft", NSHomeDirectory() + "/Applications/World of Warcraft",
                       "/Users/Shared/World of Warcraft"]
        for p in ueblich where fm.fileExists(atPath: p) { return URL(fileURLWithPath: p, isDirectory: true) }
        return nil
    }

    func setzeOrdner(_ url: URL) {
        d.set(url.path, forKey: "wowOrdner")
    }

    func installationen() -> [Installation] {
        guard let root = wowOrdner else { return [] }
        let fm = FileManager.default
        var kandidaten = [root]
        if let sub = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            kandidaten += sub.filter { $0.lastPathComponent.hasPrefix("_") }
        }
        var out: [Installation] = []
        for k in kandidaten {
            var saved: [URL] = []
            let konten = k.appendingPathComponent("WTF/Account", isDirectory: true)
            if let acc = try? fm.contentsOfDirectory(at: konten, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for a in acc {
                    let f = a.appendingPathComponent("SavedVariables/Elternabend.lua")
                    if fm.fileExists(atPath: f.path) { saved.append(f) }
                }
            }
            let addon = k.appendingPathComponent("Interface/AddOns/Elternabend", isDirectory: true)
            let hatAddon = fm.fileExists(atPath: addon.appendingPathComponent("Elternabend.toc").path)
            if !saved.isEmpty || hatAddon {
                out.append(Installation(name: k.lastPathComponent, saved: saved, addon: hatAddon ? addon : nil))
            }
        }
        return out
    }

    /// Ändert sich, sobald das Spiel seine Daten neu gespeichert hat (/reload, Logout, Beenden) –
    /// oder wenn Abgleich.lua im Addon-Ordner ersetzt wurde (Addon-Update): Dann schreibt die App sie gleich neu.
    func signatur() -> String {
        var teile: [String] = []
        for i in installationen() {
            var dateien = i.saved
            if let addon = i.addon { dateien.append(addon.appendingPathComponent("Abgleich.lua")) }
            for f in dateien {
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                teile.append(f.path + "@" + String(m?.timeIntervalSince1970 ?? 0))
            }
        }
        return teile.joined(separator: "|")
    }

    // MARK: Anzeige

    func ueberblick() -> String {
        if laeuft { return "Abgleich läuft …" }
        let meldung = d.string(forKey: "meldung") ?? ""
        if !meldung.isEmpty { return "⚠️ " + meldung }
        let t = d.double(forKey: "letzter")
        return t > 0 ? "Letzter Abgleich: " + Abgleich.zeit(t) : "Noch kein Abgleich"
    }

    var hatProblem: Bool {
        return !(d.string(forKey: "meldung") ?? "").isEmpty
    }

    func zeilen() -> [String] {
        var out = Abgleich.teile.map { $0.titel + ": " + (d.string(forKey: "status." + $0.key) ?? "noch nichts vom Addon") }
        out.append("Raid fürs Addon: " + (d.string(forKey: "status.raid") ?? "noch nicht geholt"))
        return out
    }

    static func zeit(_ t: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        let datum = Date(timeIntervalSince1970: t)
        f.dateFormat = Calendar.current.isDateInToday(datum) ? "'heute' HH:mm 'Uhr'" : "dd.MM. HH:mm 'Uhr'"
        return f.string(from: datum)
    }

    private static func jetzt() -> String {
        return zeit(Date().timeIntervalSince1970)
    }

    // MARK: Ablauf

    func neuesPasswort(_ pw: String) {
        passwort = pw
        d.set(false, forKey: "passwortFalsch")
        d.set(0.0, forKey: "gesperrtBis")
        starten()
    }

    /// Vom Hauptthread aufrufen. Läuft schon ein Abgleich, passiert nichts.
    func starten() {
        lock.lock()
        if _laeuft { lock.unlock(); return }
        _laeuft = true
        lock.unlock()
        letzterStart = Date()
        onChange?()
        queue.async { [self] in
            d.set(lauf(), forKey: "meldung")
            lock.lock()
            _laeuft = false
            lock.unlock()
            onChange?()
        }
    }

    /// Ein Durchgang. Liefert die Meldung für das Menü (leer = alles in Ordnung).
    private func lauf() -> String {
        guard let pw = passwort, !pw.isEmpty else { return "Bitte das Offizierspasswort eingeben." }
        if d.bool(forKey: "passwortFalsch") { return "Das Offizierspasswort stimmt nicht – bitte neu eingeben." }
        let bis = d.double(forKey: "gesperrtBis")
        if bis > Date().timeIntervalSince1970 {
            return "Die Webseite hat nach falschen Passwörtern gesperrt – weiter " + Abgleich.zeit(bis) + "."
        }
        let inst = installationen()
        if inst.isEmpty { return "WoW mit dem Addon Elternabend nicht gefunden – bitte den WoW-Ordner wählen." }

        var probleme: [String] = []

        // 1. Spiel → Webseite
        if let daten = neuesteDaten(inst) {
            for t in Abgleich.teile {
                guard let text = daten[t.key], !text.isEmpty else { continue }
                let h = Abgleich.abdruck(t.key, text)
                if h == d.string(forKey: "hash." + t.key) || h == d.string(forKey: "abgelehnt." + t.key) { continue }
                switch hochladen(t.key, text, pw) {
                case .ok:
                    d.set(h, forKey: "hash." + t.key)
                    d.set("hochgeladen " + Abgleich.jetzt(), forKey: "status." + t.key)
                case .passwort:
                    d.set(true, forKey: "passwortFalsch")
                    return "Das Offizierspasswort stimmt nicht – bitte neu eingeben."
                case .gesperrt:
                    return sperren()
                case .abgelehnt(let grund):
                    d.set(h, forKey: "abgelehnt." + t.key) // erst wieder versuchen, wenn sich der Inhalt ändert
                    d.set("nicht übernommen – " + grund + " (" + Abgleich.jetzt() + ")", forKey: "status." + t.key)
                    probleme.append(t.titel)
                case .netz(let grund):
                    d.set("Webseite nicht erreichbar – " + grund, forKey: "status." + t.key)
                    probleme.append(t.titel)
                }
            }
        }

        // 2. Webseite → Spiel
        switch web.post("abgleich.php", [("aktion", "raid"), ("offizier", pw)]) {
        case .failure(let e):
            d.set("Webseite nicht erreichbar – " + e.localizedDescription, forKey: "status.raid")
            probleme.append("Raid")
        case .success(let a):
            if a.status == 429 { return sperren() }
            if a.status == 403 && a.body.contains("opw") {
                d.set(true, forKey: "passwortFalsch")
                return "Das Offizierspasswort stimmt nicht – bitte neu eingeben."
            }
            if a.status == 200 && a.body.hasPrefix("#ELTERNABEND-RAID") {
                raidSchreiben(a.body, inst)
            } else if a.status == 200 && a.body.hasPrefix("KEIN-RAID") {
                raidSchreiben("", inst)
            } else {
                d.set("Antwort der Webseite nicht verstanden (HTTP " + String(a.status) + ")", forKey: "status.raid")
                probleme.append("Raid")
            }
        }

        d.set(Date().timeIntervalSince1970, forKey: "letzter")
        return probleme.isEmpty ? "" : "Problem bei: " + probleme.joined(separator: ", ")
    }

    private func sperren() -> String {
        let bis = Date().timeIntervalSince1970 + 16 * 60
        d.set(bis, forKey: "gesperrtBis")
        return "Die Webseite hat nach falschen Passwörtern gesperrt – weiter " + Abgleich.zeit(bis) + "."
    }

    /// Die jüngsten Daten des Addons (bei mehreren Konten oder WoW-Versionen zählt der neueste Stand)
    private func neuesteDaten(_ inst: [Installation]) -> [String: String]? {
        var beste: [String: String]?
        var besteZeit = -1.0
        for i in inst {
            for f in i.saved {
                guard let data = try? Data(contentsOf: f),
                      let t = LuaSaved.table(named: "ElternabendSync", in: data) else { continue }
                let z = Double(t["zeit"] ?? "") ?? 0
                if z > besteZeit {
                    besteZeit = z
                    beste = t
                }
            }
        }
        return beste
    }

    /// Fingerabdruck ohne die Teile, die sich bei jedem Speichern ändern (Zeitstempel, wer exportiert hat) –
    /// so wird nur hochgeladen, wenn sich wirklich etwas geändert hat.
    static func abdruck(_ key: String, _ text: String) -> String {
        var kern = text
        switch key {
        case "mitglieder":
            kern = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("gilde;") }.joined(separator: "\n")
        case "pinnwand":
            if let ende = text.firstIndex(of: "\n") { kern = String(text[text.index(after: ende)...]) } else { kern = "" }
        case "berufe":
            let f = text.split(separator: "^", maxSplits: 3, omittingEmptySubsequences: false)
            if f.count == 4 { kern = String(f[0]) + "^" + String(f[3]) }
        default:
            break
        }
        return sha(kern)
    }

    static func sha(_ s: String) -> String {
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func hochladen(_ key: String, _ text: String, _ pw: String) -> Ergebnis {
        let r: Result<WebAntwort, Error>
        switch key {
        case "mitglieder": r = web.post("klassenliste.php", [("aktion", "import"), ("export", text), ("offizier", pw)])
        case "berufe": r = web.post("berufe.php", [("aktion", "import"), ("export", text), ("offizier", pw)])
        case "pinnwand": r = web.post("pinnwand.php", [("export", text), ("offizier", pw)])
        default: r = web.post("abgleich.php", [("aktion", "bericht"), ("bericht", text), ("offizier", pw)])
        }
        switch r {
        case .failure(let e):
            return .netz(e.localizedDescription)
        case .success(let a):
            if a.status == 429 { return .gesperrt }
            if a.location.contains("m=opw") || (a.status == 403 && a.body.contains("opw")) { return .passwort }
            if key == "bericht" {
                if a.status == 200 && a.body.hasPrefix("OK") { return .ok }
                let zeile = a.body.split(separator: "\n").first.map(String.init) ?? ""
                return .abgelehnt(Abgleich.grund(zeile.replacingOccurrences(of: "FEHLER ", with: ""), a.status))
            }
            if (300..<400).contains(a.status) && a.location.contains("m=import") { return .ok }
            var code = ""
            if let r = a.location.range(of: "m=") {
                code = String(a.location[r.upperBound...].prefix { $0 != "&" && $0 != "#" })
            }
            return .abgelehnt(Abgleich.grund(code, a.status))
        }
    }

    private static func grund(_ code: String, _ status: Int) -> String {
        switch code {
        case "format", "kein-bericht": return "die Webseite hat den Text nicht erkannt"
        case "leer": return "der Text enthält keine Einträge"
        case "gross", "bericht-gross": return "der Text ist zu groß"
        case "alt": return "das Addon ist zu alt für die Webseite"
        case "setup": return "die Webseite ist noch nicht eingerichtet"
        case "kein-raid": return "dieser Raid steht nicht (mehr) im Raidplaner"
        case "schreiben": return "die Webseite konnte nicht speichern"
        case "": return "HTTP " + String(status)
        default: return code
        }
    }

    /// Schreibt die Daten der Webseite als Abgleich.lua in den Addon-Ordner. Das Addon liest sie beim nächsten
    /// Einloggen oder /reload. „raid“ ist leer, wenn kein Raid ansteht.
    private func raidSchreiben(_ raid: String, _ inst: [Installation]) {
        let h = Abgleich.sha(raid)
        if h != d.string(forKey: "raidHash") {
            d.set(h, forKey: "raidHash")
            d.set(Int(Date().timeIntervalSince1970), forKey: "raidZeit")
        }
        let zeit = d.integer(forKey: "raidZeit")
        let inhalt = """
        -- Geschrieben von der Mac-App „Elternabend Abgleich“ – bitte nicht von Hand ändern.
        -- Daten von gilde-elternabend.de: nächster Raid mit Anmeldungen, Raidgruppen, Soft-Reserves und Terminen.
        ElternabendAbgleich = {
            v = 1,
            app = \(LuaSaved.quote(appVersion)),
            zeit = \(zeit),
            raid = \(LuaSaved.quote(raid)),
        }

        """

        var geschrieben = 0, aktuell = 0, zuAlt = 0, fehler = 0
        for i in inst {
            guard let addon = i.addon else { continue }
            let toc = (try? String(contentsOf: addon.appendingPathComponent("Elternabend.toc"), encoding: .utf8)) ?? ""
            if !toc.contains("Abgleich.lua") { zuAlt += 1; continue }
            let datei = addon.appendingPathComponent("Abgleich.lua")
            if let vorhanden = try? String(contentsOf: datei, encoding: .utf8), vorhanden == inhalt { aktuell += 1; continue }
            do {
                try inhalt.write(to: datei, atomically: true, encoding: .utf8)
                geschrieben += 1
            } catch {
                fehler += 1
            }
        }

        // Name des Raids aus der Zeile „raid;ID;Name;Vorlage;Datum“
        var name = "kein Raid geplant"
        for zeile in raid.split(separator: "\n") where zeile.hasPrefix("raid;") {
            let f = zeile.split(separator: ";", omittingEmptySubsequences: false)
            if f.count >= 5 { name = String(f[2]) + " (" + String(f[4]) + ")" }
            break
        }
        let status: String
        if fehler > 0 {
            status = name + " – konnte nicht in den Addon-Ordner schreiben"
        } else if geschrieben + aktuell == 0 {
            status = zuAlt > 0 ? "Addon-Version ohne Abgleich – bitte das Addon aktualisieren" : "Addon Elternabend nicht gefunden"
        } else {
            status = name + " – Stand " + Abgleich.zeit(Double(zeit))
        }
        d.set(status, forKey: "status.raid")
    }
}
