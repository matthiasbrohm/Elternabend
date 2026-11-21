-- Gilde » Raidwünsche: raiden ja/ab und zu/eher nicht, Tage × Startzeiten, Rollen – mit Auswertung

local function Gilde(officer)
    local w = login({
        guild = "Elternabend", officer = officer,
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true, classFile = "PALADIN" },
            { name = "Greta Glutherz", online = false, classFile = "WARLOCK" },
            { name = "Beta Eisenfuss", online = false, classFile = "WARRIOR" },
        },
    })
    w:advance(30)
    w:clear()
    return w
end

-- Raidwunsch eines anderen, wie er über PRF ankommt
local function Wunsch(w, name, wish, raid, roles)
    local rec = table.concat({ name, w.env.time(), "", 0, "", wish, raid, roles }, "^")
    w:receive("PRF\t" .. rec, "GUILD", name)
end

test("Raidwünsche: ankommende Wünsche werden gezählt und die beliebtesten Termine stehen oben", function()
    local w = Gilde(true)
    local ns, P = w.ns, w.ns.Profile
    -- Sa (Tag 6) ab 10:00 = Bit 2 → "02"; So 21:00 = Bit 128 → "80"
    Wunsch(w, "Beta Lux", 1, "00000000000280", 2)       -- Heiler: Sa 10:00, So 21:00
    Wunsch(w, "Greta Glutherz", 2, "00000000000200", 4) -- DD, ab und zu: Sa 10:00
    Wunsch(w, "Beta Eisenfuss", 3, "", 1)               -- eher nicht
    equal(P.WishText(P:For(ns.Members:Find("Beta Lux"))), "ja, gern – Sa ab 10:00 · So ab 21:00 – Heiler")
    ns.UI:Show("raidwunsch")
    w:advance(1)
    local p = ns.UI.panels.raidwunsch
    check(p:IsShown() and ns.UI.subTabs.raidwunsch:IsShown(), "Reiter fehlt")
    equal(p.tiles[2][6].count:GetText(), 2)
    equal(p.tiles[8][7].count:GetText(), 1)
    check(p.summary:GetText():find("2 wollen raiden"), p.summary:GetText())
    check(p.summary:GetText():find("1 eher nicht"), p.summary:GetText())
    check(p.rows[1].text:GetText():find("Sa ab 10:00") and p.rows[1].text:GetText():find("2 würden"), p.rows[1].text:GetText())
    check(p.rows[1].text:GetText():find("1 Heiler, 1 DD"), p.rows[1].text:GetText())
    -- Gildenleitung: Auswertung als Text
    check(p.export:IsShown(), "Knopf für die Leitung fehlt")
    local text = p:ExportText()
    check(text:find("• Sa ab 10:00 Uhr: 2 %(1 Heiler, 1 DD%)"), text)
    noErrors(w)
end)

test("Raidwünsche: eigenen Wunsch anklicken, speichern und weitergeben", function()
    local w = Gilde(false)
    local ns, P = w.ns, w.ns.Profile
    ns.UI:Show("raidwunsch")
    local p = ns.UI.panels.raidwunsch
    check(not p.export:IsShown(), "Auswertung kopieren nur für die Leitung")
    -- Zeit anklicken setzt „Ja, gern“ von selbst
    p.tiles[2][6]:Click()
    equal(p.wish, 1)
    p.tiles[2][7]:Click()
    p.roleButtons[1]:Click() -- Tank
    p.roleButtons[3]:Click() -- DD
    equal(P.Me().wish, nil)
    p.save:Click()
    w:advance(2)
    equal(P.Me().wish, 1)
    equal(P.Me().raid, "00000000000202")
    equal(P.Me().roles, 5)
    seen(w, "print", "Dein Raidwunsch: ja, gern – am Wochenende ab 10:00 – Tank/DD")
    seen(w, "comm", "PRF.*%^1%^00000000000202%^5")
    -- „Eher nicht“: Zeiten zählen nicht mehr
    p.wishButtons[3]:Click()
    p.save:Click()
    equal(P.WishText(P.Me()), "eher nicht")
    check(not p.tiles[2][6].fill:IsShown(), "Feld noch golden")
    noErrors(w)
end)

test("Raidwünsche: ein älteres Addon reicht den Stand ohne Raidwunsch weiter – der mit Wunsch gewinnt", function()
    local w = Gilde(false)
    local P = w.ns.Profile
    local t = w.env.time()
    w:receive("PRF\t" .. table.concat({ "Beta Lux", t, "0404000", 0, "" }, "^"), "GUILD", "Beta Lux")
    local e = w.ns.Members:Find("Beta Lux")
    equal(P:For(e).wish, nil)
    w:receive("PRF\t" .. table.concat({ "Beta Lux", t, "0404000", 0, "", 1, "00000000000080", 2 }, "^"), "GUILD", "Beta Lux")
    equal(P:For(e).wish, 1)
    -- und umgekehrt nicht wieder zurück
    w:receive("PRF\t" .. table.concat({ "Beta Lux", t, "0404000", 0, "" }, "^"), "GUILD", "Beta Lux")
    equal(P:For(e).wish, 1)
    noErrors(w)
end)
