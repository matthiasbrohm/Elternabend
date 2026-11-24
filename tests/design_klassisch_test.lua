-- Design „Klassisch“ mit den Bedienelementen des Spiels: alle Reiter und Dialoge lassen sich ohne Fehler öffnen

test("Design Klassisch (rote Spielknöpfe): alle Reiter, Einstellungen und Design-Auswahl öffnen ohne Fehler", function()
    local w = login({ guild = "Elternabend", raid = true, leader = true, db = { skin = "klassisch" } })
    w:advance(30)
    local ns = w.ns
    check(ns.Theme.GameControls(), "Spielknöpfe nicht aktiv")
    for _, key in ipairs({ "start", "mitglieder", "spielzeiten", "raidwunsch", "kalender", "pinnwand", "berufe", "gruppen",
        "gruppe", "notizen", "raid", "raidgruppen", "abstimmung", "sr", "loot", "history", "taktik", "fame", "web", "leitung" }) do
        ns.UI:Show(key)
        w:advance(1)
    end
    ns.UI:ShowOptions()
    ns.UI:ShowSkinPicker()
    -- Umschaltknöpfe (Karteikarten/Liste) mit Spielknöpfen
    ns.UI:Show("pinnwand")
    w:advance(1)
    noErrors(w)
end)
