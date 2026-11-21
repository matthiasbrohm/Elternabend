-- Gilde » Spielzeiten: eigener Unterreiter mit großem Raster, Zahlen je Feld und „Spielen zu ähnlichen Zeiten“

local function Gilde()
    local w = login({
        guild = "Elternabend",
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true, classFile = "PALADIN" },
            { name = "Greta Glutherz", online = false, classFile = "WARLOCK" },
            { name = "Beta Eisenfuss", online = false, classFile = "WARRIOR" },
        },
    })
    w:advance(30)
    local ns = w.ns
    -- Andere haben schon eingetragen: Beta Lux Di/Do abends, Greta Glutherz Di abends und spät
    local function Set(name, times, note)
        local e = ns.Members:Find(name)
        check(e, name .. " nicht in der Gildenliste")
        ns.db.profiles[e.key] = { name = e.name, t = w.env.time(), times = times, steps = 0, note = note or "" }
    end
    Set("Beta Lux", "0404000", "meist ab 20:30")
    Set("Greta Glutherz", "0c00000")
    w:clear()
    return w
end

test("Spielzeiten: eigener Unterreiter unter Gilde, Zahlen im Raster, Speichern", function()
    local w = Gilde()
    local ns = w.ns
    ns.UI:Show("spielzeiten")
    local p = ns.UI.panels.spielzeiten
    check(p:IsShown(), "Reiter nicht offen")
    check(ns.UI.subnav:IsShown(), "Unterleiste fehlt")
    check(ns.UI.subTabs.mitglieder:IsShown() and ns.UI.subTabs.spielzeiten:IsShown(), "Unterreiter fehlen")
    check(not ns.UI.subTabs.sr:IsShown(), "Raid-Unterreiter sichtbar")
    -- Dienstag abends (Tag 2, Zeitfenster 3): zwei aus der Gilde
    equal(p.tiles[3][2].count:GetText(), 2)
    equal(p.tiles[3][4].count:GetText(), 1)
    equal(p.tiles[1][1].count:GetText(), "")
    -- Noch nichts eingetragen: niemand passt
    check(p.empty:IsShown(), "Hinweis fehlt")
    -- Di und Do abends anklicken: Vorschau sofort, gespeichert erst mit „Speichern“
    p.tiles[3][2]:Click()
    p.tiles[3][4]:Click()
    check(p.tiles[3][2].fill:IsShown(), "Feld nicht golden")
    equal(ns.Profile.Me().times, nil)
    check(p.rows[1]:IsShown() and p.rows[1].text:GetText():find("Beta Lux"), "Beta Lux fehlt oben")
    check(p.rows[1].text:GetText():find("2 gemeinsame Zeiten"), p.rows[1].text:GetText())
    check(p.rows[2].text:GetText():find("Greta Glutherz") and p.rows[2].text:GetText():find("1 gemeinsame Zeit"), "Greta fehlt")
    check(not p.rows[3]:IsShown(), "zu viele Zeilen")
    p.save:Click()
    w:advance(2)
    equal(ns.Profile.Me().times, "0404000")
    seen(w, "print", "Deine Spielzeiten: abends Di, Do")
    seen(w, "comm", "PRF")
    noErrors(w)
end)

test("Spielzeiten: „Meine Spielzeiten“ und /ea spielzeiten öffnen den Unterreiter; Gilde ist dabei aktiv", function()
    local w = Gilde()
    local ns = w.ns
    ns.UI:Show("mitglieder")
    check(ns.UI.subnav:IsShown(), "Unterleiste fehlt bei Mitglieder")
    ns.UI:ShowPlayTimes()
    equal(ns.UI.currentTab, "spielzeiten")
    check(ns.UI.panels.spielzeiten:IsShown(), "Reiter nicht offen")
    check(not ns.UI.panels.mitglieder:IsShown(), "Mitglieder noch offen")
    -- Ungespeichertes verfällt beim Verlassen
    ns.UI.panels.spielzeiten.tiles[1][1]:Click()
    ns.UI:Show("start")
    ns.UI:Show("spielzeiten")
    check(not ns.UI.panels.spielzeiten.tiles[1][1].fill:IsShown(), "Entwurf nicht verworfen")
    noErrors(w)
end)
