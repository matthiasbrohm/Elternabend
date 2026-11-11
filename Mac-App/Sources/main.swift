// Elternabend Abgleich – kleine Menüleisten-App für den Mac.
// Gleicht das Addon „Elternabend“ mit gilde-elternabend.de ab, ohne Kopieren und Einfügen:
//   Spiel → Webseite: Klassenliste, Pinnwand, Berufe, Raid-Bericht (liest die SavedVariables nach /reload oder Logout)
//   Webseite → Spiel: nächster Raid mit Anmeldungen, Raidgruppen, Soft-Reserves und Terminen (schreibt Abgleich.lua ins Addon)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
