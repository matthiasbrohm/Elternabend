-- Raid an die Gruppe: Die Raidleitung lädt den Raid (App oder Raid-Text), alle aus der Gilde in der Gruppe bekommen ihn

local RAID = table.concat({
    "#ELTERNABEND-RAID 1",
    "raid;abcd1234;Gemütlicher Schlafsack;schlafsack;2026-11-24 21:00",
    "spieler;Beta Lux;Paladin;tank;dabei",
    "spieler;Greta Glutherz;Priester;heal;dabei",
    "spieler;Mira Mondschein;Magier;dd;vielleicht",
    "gruppe;1;Beta Lux;Greta Glutherz",
    "sr;Greta Glutherz;19019;Donnerzorn;Ragnaros",
    "#ENDE",
}, "\n")

local function Welt(opts)
    local w = login({ guild = opts.guild or "Elternabend", raid = true, leader = opts.leader })
    w:advance(30)
    local ns = w.ns
    local me = ns.UnitFullName("player")
    ns.IsTrusted = function(name)
        if opts.leader then return ns.SameName(name, me) end
        return ns.SameName(name, "Beta Lux")
    end
    w:clear()
    return w
end

local function Teile(text)
    -- So kommt der Raid-Text an: PLN \t ID \t Anzahl \t Nr \t Teil
    return "PLN\t4711\t1\t1\t" .. text
end

test("Raid teilen: Raidleitung lädt den Raid in der Gruppe – er geht von selbst an alle", function()
    local w = Welt({ leader = true })
    check(w.ns.Web:Import(RAID), "Import fehlgeschlagen")
    seen(w, "print", "geht automatisch an alle in der Gruppe")
    w:advance(2)
    seen(w, "comm", "PLN .*Gemütlicher Schlafsack")
    seen(w, "comm", "SRS")
    noErrors(w)
end)

test("Raid teilen: Mitglied bekommt Anmeldungen, Raidgruppen und Soft-Reserves von der Raidleitung", function()
    local w = Welt({})
    w:receive(Teile(RAID), "RAID", "Beta Lux")
    local plan = w.ns.db.plan
    check(plan and plan.title == "Gemütlicher Schlafsack", "Raid nicht übernommen")
    equal(plan.from, "Beta Lux")
    check(plan.signups["greta glutherz"], "Anmeldung fehlt")
    check(plan.groups and plan.groups[1], "Raidgruppe fehlt")
    equal(w.ns.SR:Count(), 1)
    seen(w, "print", "Raid „Gemütlicher Schlafsack“ von Beta Lux übernommen: 3 Anmeldungen, 1 Soft%-Reserves")
    -- derselbe Raid noch einmal: keine zweite Meldung
    w:clear()
    w:receive(Teile(RAID), "RAID", "Beta Lux")
    notSeen(w, "print", "übernommen")
    -- nicht weiterverteilt
    w:advance(3)
    notSeen(w, "comm", "PLN")
    noErrors(w)
end)

test("Raid teilen: von Nicht-Leitung oder als Gast wird nichts übernommen", function()
    local w = Welt({})
    w:receive(Teile(RAID), "RAID", "Greta Glutherz")
    check(not w.ns.db.plan or w.ns.db.plan.title ~= "Gemütlicher Schlafsack", "von Nicht-Leitung übernommen")
    local g = Welt({ guild = "Andere Gilde" })
    g:receive(Teile(RAID), "RAID", "Beta Lux")
    check(not g.ns.db.plan or g.ns.db.plan.title ~= "Gemütlicher Schlafsack", "als Gast übernommen")
    noErrors(w)
    noErrors(g)
end)

test("Raid teilen: Nachzügler fragt nach (SRQ) – die Raidleitung schickt den Raid", function()
    local w = Welt({ leader = true })
    w.ns.Web:Import(RAID)
    w:advance(3)
    w:clear()
    w:receive("SRQ", "RAID", "Mira Mondschein")
    w:advance(8)
    seen(w, "comm", "PLN .*Gemütlicher Schlafsack")
    noErrors(w)
end)
