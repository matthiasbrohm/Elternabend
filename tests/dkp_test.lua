-- DKP: Punktestände aus dem Raidplaner, verdeckte Bieterrunde, Vergabe zieht das Gebot ab

local RAID = table.concat({
    "#ELTERNABEND-RAID 1",
    "raid;abcd1234;Hyjalgipfel;hyjal;2026-11-28 21:00",
    "spieler;Beta Lux;Paladin;tank;dabei",
    "dkpregel;10",
    "dkp;Beta Lux;50",
    "dkp;Greta Glutherz;120",
    "dkp;Anna Sturmwind;30",
    "#ENDE",
}, "\n")

local function Raid(lead)
    local w = login({ guild = "Elternabend", raid = true, leader = lead })
    w:advance(30)
    local ns = w.ns
    local me = ns.UnitFullName("player")
    ns.IsTrusted = function(name) return lead and ns.SameName(name, me) or (not lead and ns.SameName(name, "Beta Lux")) end
    ns.Raid.members, ns.Raid.byKey = {}, {}
    for _, name in ipairs({ me, "Beta Lux", "Greta Glutherz" }) do
        local m = { name = name, key = ns.NameKey(name), online = true }
        table.insert(ns.Raid.members, m)
        ns.Raid.byKey[m.key] = m
    end
    check(ns.Web:Import(RAID), "Import fehlgeschlagen")
    w:clear()
    return w
end

local LINK = "|cffa335ee|Hitem:30904::::::::60:::::|h[Savior's Grasp]|h|r"

test("DKP: Plündermeister startet eine Bieterrunde, Gebote per Addon und Flüstern, höchstes gewinnt und zahlt", function()
    local w = Raid(true)
    local ns = w.ns
    equal(ns.DKP:Points("Greta Glutherz"), 120)
    ns.Loot:StartRoll({ itemId = 30904, link = LINK })
    w:advance(1)
    seen(w, "chat", "Bieterrunde %(DKP%)")
    seen(w, "comm", "BIDOPEN")
    notSeen(w, "comm", "ROLL")
    -- Beta Lux bietet 30 per Addon, Greta Glutherz flüstert „biete 40“, dann zu viel
    w:receive("BID\t30", "WHISPER", "Beta Lux")
    w:fire("CHAT_MSG_WHISPER", "biete 40", "Greta Glutherz")
    w:fire("CHAT_MSG_WHISPER", "biete 500", "Greta Glutherz")
    w:advance(1)
    seen(w, "comm", "BIDOK 30 Gebot angenommen")
    seen(w, "chat", "Du hast nur 120 DKP")
    -- Unter dem Mindestgebot
    w:receive("BID\t5", "WHISPER", "Beta Lux")
    local sorted = ns.Loot:GetSortedRolls()
    equal(sorted[1].name, "Greta Glutherz")
    equal(sorted[1].roll, 40)
    equal(sorted[2].roll, 30) -- das Gebot unter Mindestgebot gilt nicht
    ns.Loot:EndRoll()
    w:advance(1)
    seen(w, "chat", "Höchstes Gebot für .*Greta Glutherz %(40 DKP%)")
    ns.Loot:Award("Greta Glutherz")
    w:advance(1)
    equal(ns.DKP:Points("Greta Glutherz"), 80)
    equal(ns.db.history[1].label, "DKP")
    equal(ns.db.history[1].roll, 40)
    seen(w, "comm", "AWARD .*Greta Glutherz 40")
    noErrors(w)
end)

test("DKP: Spieler bekommt die Bieterrunde angesagt und bietet mit /ea biete", function()
    local w = Raid(false)
    local ns = w.ns
    w:receive("BIDOPEN\t" .. LINK .. "\t20\t10", "RAID", "Beta Lux")
    seen(w, "print", "Bieterrunde:.*du hast 30 DKP")
    check(not ns.DKP:Bid(5), "unter Mindestgebot angenommen")
    check(not ns.DKP:Bid(50), "mehr als eigene Punkte angenommen")
    check(ns.DKP:Bid(25), "Gebot abgelehnt")
    w:advance(1)
    seen(w, "comm", "WHISPER Beta Lux BID 25")
    -- Nach der Vergabe ziehen alle den Preis ab
    w:receive("AWARD\t" .. LINK .. "\tGreta Glutherz\t40", "RAID", "Beta Lux")
    equal(ns.DKP:Points("Greta Glutherz"), 80)
    noErrors(w)
end)

test("DKP: Raid ohne DKP-Zeilen schaltet die Bieterrunde wieder ab", function()
    local w = Raid(true)
    local ns = w.ns
    ns.Web:Import("#ELTERNABEND-RAID 1\nraid;abcd5678;Barrow Deeps;barrow;2026-11-29 21:00\nspieler;Beta Lux;Paladin;tank;dabei\n#ENDE")
    check(not ns.DKP:Active(), "DKP noch aktiv")
    ns.Loot:StartRoll({ itemId = 30904, link = LINK })
    w:advance(1)
    seen(w, "chat", "Hauptspec /roll")
    noErrors(w)
end)
