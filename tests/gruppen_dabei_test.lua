-- Reiter „Gruppen“: Unterreiter „Offene Gruppen“ / „Eigene Gruppe“ und „Wer ist dabei?“

local function Welt()
    local w = login({ guild = "Elternabend", roster = {
        { name = "Greta Glutherz", online = true, class = "PRIEST" },
        { name = "Beta Lux", online = true, class = "PALADIN" },
        { name = "Torben Eisenbart", online = true, class = "WARRIOR" },
    } })
    w:advance(40)
    return w
end

test("Gruppen: Hauptreiter öffnet „Offene Gruppen“, Unterreiter „Eigene Gruppe“ zeigt das Formular", function()
    local w = Welt()
    w.ns.UI:Show("gruppen")
    local UI = w.ns.UI
    check(UI.panels.gruppen:IsShown(), "Offene Gruppen nicht offen")
    check(UI.subnav:IsShown(), "keine Unterleiste")
    check(UI.subTabs.gruppen:IsShown() and UI.subTabs.gruppe:IsShown(), "Unterreiter fehlen")
    check(not UI.subTabs.raid:IsShown(), "Raid-Unterreiter sichtbar")
    UI:Show("gruppe")
    check(UI.panels.gruppe:IsShown() and not UI.panels.gruppen:IsShown(), "Eigene Gruppe nicht offen")
    check(UI.panels.gruppen.post:IsVisible() or UI.panels.gruppen.post:IsShown(), "Knopf „Gruppe suchen“ fehlt")
    -- Raid zeigt wieder seine Unterreiter
    UI:Show("raid")
    check(UI.subTabs.raid:IsShown() and not UI.subTabs.gruppe:IsShown(), "Unterreiter nicht umgeschaltet")
    noErrors(w)
end)

test("Wer ist dabei: Suchender schickt Meldungen, andere sehen sie mit Rolle", function()
    local w = Welt()
    local G = w.ns.Groups
    G:Post("Halle der Thanen", { tank = 1, heal = 1, dd = 3 }, "")
    w:advance(3)
    local id = G.mine.id
    w:receive(table.concat({ "LFGJOIN", id, "dd", "PRIEST", "" }, "\t"), "WHISPER", "Greta Glutherz")
    w:receive(table.concat({ "LFGJOIN", id, "tank", "PALADIN", "Beta Eisenfuss" }, "\t"), "WHISPER", "Beta Lux")
    local who = G:Who(G.mine)
    equal(#who, 2)
    w:clear()
    w:advance(4)
    seen(w, "comm", "LFGWHO")
    -- Meldung „Eigene Gruppe“: rote Plakette
    equal(G:NewApplicants(), 2)
    noErrors(w)

    -- Ein anderer bekommt Gesuch und „Wer ist dabei?“
    local w2 = Welt()
    local now = 0
    w2:receive(table.concat({ "LFG", "4711", "Halle der Thanen", 1, 1, 3, "", now, "" }, "\t"), "GUILD", "Torben Eisenbart")
    local data = "4711\ndd,Greta Glutherz,PRIEST,gemeldet\ntank,Beta Eisenfuss,PALADIN,umloggen"
    w2:receive(table.concat({ "LFGWHO", "9", 1, 1, data }, "\t"), "GUILD", "Torben Eisenbart")
    local g = w2.ns.Groups.list["4711"]
    equal(#g.who, 2)
    equal(g.who[2].name, "Beta Eisenfuss")
    -- nur vom Suchenden selbst
    w2:receive(table.concat({ "LFGWHO", "10", 1, 1, "4711\ndd,Fremd,MAGE,gemeldet" }, "\t"), "GUILD", "Beta Lux")
    equal(#w2.ns.Groups.list["4711"].who, 2)
    -- neues LFG (z. B. weniger gesucht) behält die Liste
    w2:receive(table.concat({ "LFG", "4711", "Halle der Thanen", 1, 1, 2, "", 30, "" }, "\t"), "GUILD", "Torben Eisenbart")
    equal(#w2.ns.Groups.list["4711"].who, 2)
    -- angezeigt rechts unter „Wer ist dabei?“, Tank zuerst
    w2.ns.UI:Show("gruppen")
    local p = w2.ns.UI.panels.gruppen
    p.selected = "4711"
    w2:call(p.Refresh, p)
    check(p.whoTitle:GetText() == "Halle der Thanen", p.whoTitle:GetText())
    check(p.whoRows[1]:GetText():find("Tank", 1, true) and p.whoRows[1]:GetText():find("Beta Eisenfuss", 1, true), p.whoRows[1]:GetText())
    check(p.whoRows[2]:GetText():find("Greta Glutherz", 1, true) and p.whoRows[2]:GetText():find("gemeldet", 1, true), p.whoRows[2]:GetText())
    noErrors(w2)
end)

test("Wer ist dabei: ohne Angaben ein Hinweis, Absagen fallen raus", function()
    local w = Welt()
    w:receive(table.concat({ "LFG", "55", "Todesminen", 1, 0, 0, "", 0, "" }, "\t"), "GUILD", "Torben Eisenbart")
    w.ns.UI:Show("gruppen")
    local p = w.ns.UI.panels.gruppen
    p.selected = "55"
    w:call(p.Refresh, p)
    check(p.whoRows[1]:GetText():find("Noch keine Angaben", 1, true), p.whoRows[1]:GetText())
    local G = w.ns.Groups
    G:Post("Gnomeregan", { tank = 1, heal = 0, dd = 1 }, "")
    w:receive(table.concat({ "LFGJOIN", G.mine.id, "dd", "PRIEST", "" }, "\t"), "WHISPER", "Greta Glutherz")
    G:Decline(G.applicants[w.ns.NameKey("Greta Glutherz")])
    equal(#G:Who(G.mine), 0)
    noErrors(w)
end)
