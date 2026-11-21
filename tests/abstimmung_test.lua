-- Raid » Abstimmung: Dafür / Dagegen / Passt beides

local function Raid(lead)
    local w = login({ guild = "Elternabend", raid = true, leader = lead })
    w:advance(30)
    local ns = w.ns
    -- Gruppe und Leitung nachstellen: Beta Lux leitet, wenn nicht ich
    local me = ns.UnitFullName("player")
    ns.IsTrusted = function(name) return lead and ns.SameName(name, me) or (not lead and ns.SameName(name, "Beta Lux")) end
    ns.Raid.members = {}
    for _, m in ipairs({ { me, "PALADIN" }, { "Beta Lux", "PALADIN" }, { "Greta Glutherz", "WARLOCK" } }) do
        table.insert(ns.Raid.members, { name = m[1], key = ns.NameKey(m[1]), classFile = m[2] })
    end
    w:clear()
    return w
end

test("Abstimmung: Leitung fragt, Stimmen werden gezählt, Ergebnis in den Raidchat", function()
    local w = Raid(true)
    local V = w.ns.Vote
    check(V:Start("Noch ein Boss?", true), "Start klappt nicht")
    w:advance(2)
    seen(w, "comm", "VT S %d+ Noch ein Boss%?")
    seen(w, "chat", "Abstimmung: Noch ein Boss%?")
    local id = V.current.id
    V:Cast(1)
    w:receive(table.concat({ "VT", "V", id, 2 }, "\t"), "RAID", "Beta Lux")
    w:receive(table.concat({ "VT", "V", id, 1 }, "\t"), "RAID", "Greta Glutherz")
    w:receive(table.concat({ "VT", "V", id, 3 }, "\t"), "RAID", "Greta Glutherz") -- umentschieden
    equal(V:CountText(), "1 dafür, 1 dagegen, 1 passt beides")
    -- alle haben abgestimmt: die Leitung bekommt Bescheid
    seen(w, "print", "Alle haben abgestimmt")
    w:clear()
    V:Announce()
    w:advance(2)
    seen(w, "chat", "Ergebnis der Abstimmung „Noch ein Boss%?“: 1 dafür, 1 dagegen, 1 passt beides")
    V:End()
    w:advance(1)
    seen(w, "comm", "VT E " .. id)
    -- nach dem Ende zählen keine Stimmen mehr
    w:receive(table.concat({ "VT", "V", id, 1 }, "\t"), "RAID", "Beta Lux")
    equal(V:CountText(), "1 dafür, 1 dagegen, 1 passt beides")
    noErrors(w)
end)

test("Abstimmung: Mitglied bekommt das Fenster, stimmt ab; nur die Leitung darf starten", function()
    local w = Raid(false)
    local V = w.ns.Vote
    check(not V:Start("Pause?"), "Nicht-Leitung darf starten")
    -- Fremder ohne Rang startet: ignoriert
    w:receive(table.concat({ "VT", "S", "11", "Fake?" }, "\t"), "RAID", "Greta Glutherz")
    equal(V.current, nil)
    w:receive(table.concat({ "VT", "S", "12", "Kurze Pause?" }, "\t"), "RAID", "Beta Lux")
    check(V.current and V.current.question == "Kurze Pause?", "Frage nicht angekommen")
    check(V.popup and V.popup:IsShown(), "Fenster nicht offen")
    V.popup.buttons[3]:Click()
    equal(V:Mine(), 3)
    w:advance(1)
    seen(w, "comm", "VT V 12 3")
    -- Reiter Raid » Abstimmung zeigt Namen in den Spalten und wer fehlt
    w.ns.UI:Show("abstimmung")
    local p = w.ns.UI.panels.abstimmung
    w:call(p.Refresh, p)
    check(p.cols[3].names:GetText():find(w.ns.ShortName(w.ns.UnitFullName("player")), 1, true), p.cols[3].names:GetText())
    check(p.missing:GetText():find("Beta Lux", 1, true) and p.missing:GetText():find("Greta Glutherz", 1, true), p.missing:GetText())
    check(not p.start:IsEnabled(), "Start-Knopf für Nicht-Leitung an")
    -- Leitung beendet
    w:receive(table.concat({ "VT", "E", "12" }, "\t"), "RAID", "Beta Lux")
    check(not V.current.open, "nicht beendet")
    noErrors(w)
end)
