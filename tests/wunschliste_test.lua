-- Loot-Wunschlisten: Prio aus dem Raidplaner, Tooltip/Beute-Hinweis, Abhaken und Weitergabe in der Gruppe

local RAID = table.concat({
    "#ELTERNABEND-RAID 1",
    "raid;abcd1234;Onyxias Hort;onyxia;2026-11-28 21:00",
    "spieler;Anna Sturmwind;Paladin;heal;dabei",
    "spieler;Beta Lux;Paladin;tank;dabei",
    "wunsch;Beta Lux;18813;1",
    "wunsch;Greta Glutherz;18813;2",
    "wunsch;Anna Sturmwind;18813;3",
    "prio;18813;Greta Glutherz,Beta Lux,Anna Sturmwind",
    "wunsch;Anna Sturmwind;17078;1",
    "prio;17078;Anna Sturmwind",
    "#ENDE",
}, "\n")

local function Raid(w)
    local ns = w.ns
    ns.Raid.members = {}
    ns.Raid.byKey = {}
    for _, name in ipairs({ "Anna Sturmwind", "Beta Lux" }) do
        local m = { name = name, key = ns.NameKey(name), online = true }
        table.insert(ns.Raid.members, m)
        ns.Raid.byKey[m.key] = m
    end
end

test("Wunschliste: Prio aus dem Raid-Text, wer gerade dran ist, Abhaken", function()
    local w = login({ guild = "Elternabend" })
    w:advance(5)
    local ns = w.ns
    check(ns.Web:Import(RAID), "Import fehlgeschlagen")
    seen(w, "print", "Wunschliste mit Prio für 2 Items")
    seen(w, "print", "Du bist als Nächstes dran bei")
    equal(ns.WL:Count(), 2)
    Raid(w)
    -- Greta Glutherz ist nicht im Raid: Beta Lux ist dran, danach Anna Sturmwind
    equal(ns.WL:Next(18813).name, "Beta Lux")
    equal(ns.WL:Label(18813), "Beta Lux · danach Anna Sturmwind")
    equal(ns.WL:Rank(18813, ns.NameKey("Greta Glutherz")), 2)
    -- Beta Lux bekommt den Ring: Anna rückt nach
    ns.WL:MarkWon(18813, "Beta Lux")
    equal(ns.WL:Next(18813).name, "Anna Sturmwind")
    equal(#ns.WL:Prio(18813), 2)
    noErrors(w)
end)

test("Wunschliste: Weitergabe in der Gruppe (ohne die, die es schon haben) und neuere Liste bleibt", function()
    local w = login({ guild = "Elternabend" })
    w:advance(5)
    local ns = w.ns
    ns.Web:Import(RAID)
    ns.WL:MarkWon(18813, "Greta Glutherz")
    local text = ns.WL:Serialize()
    local at = ns.WL:Data().importedAt
    ns.WL:Clear()
    equal(ns.WL:Count(), 0)
    ns.WL:ImportSerialized(text, "Beta Lux")
    equal(ns.WL:Count(), 2)
    equal(#ns.WL:Prio(18813), 2)
    equal(ns.WL:Prio(18813)[1].name, "Beta Lux")
    equal(ns.WL:Rank(18813, ns.NameKey("Anna Sturmwind")), 3)
    -- Eine ältere Liste überschreibt die eigene nicht
    ns.WL:ImportSerialized((text:gsub("^%d+", tostring(at - 100))) .. ";99999:Niemand:", "Mira")
    equal(ns.WL:Data().prio[99999], nil)
    noErrors(w)
end)

test("Wunschliste: Raid ohne Wunschlisten-Zeilen entfernt eine alte Liste", function()
    local w = login({ guild = "Elternabend" })
    w:advance(5)
    local ns = w.ns
    ns.Web:Import(RAID)
    equal(ns.WL:Count(), 2)
    ns.Web:Import("#ELTERNABEND-RAID 1\nraid;abcd5678;Barrow Deeps;barrow;2026-11-29 21:00\nspieler;Beta Lux;Paladin;tank;dabei\n#ENDE")
    equal(ns.WL:Data(), nil)
    noErrors(w)
end)
