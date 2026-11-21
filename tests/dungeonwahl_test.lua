-- Gruppensuche: Dungeon aus einer Liste wählen (mit empfohlenem Stufenbereich), Freifeld bleibt.

local function Welt(extra)
    local opts = { guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    w:advance(30)
    w:clear()
    return w
end

test("Dungeonliste: vollständig, sinnvolle Stufen, nach Stufe sortiert", function()
    local w = Welt()
    local list = w.ns.Groups.DUNGEONS
    equal(#list, 30)
    local seenNames = {}
    for i, d in ipairs(list) do
        check(d.name ~= "" and d.zone ~= "", "Name oder Ort fehlt bei Nr. " .. i)
        check(d.min >= 1 and d.max <= 60 and d.min <= d.max, "Stufen unsinnig: " .. d.name)
        check(not seenNames[d.name], "doppelt: " .. d.name)
        seenNames[d.name] = true
        if i > 1 then check(list[i - 1].min <= d.min, "nicht nach Stufe sortiert: " .. d.name) end
    end
end)

test("Dungeon zum Gesuchstext: genau, ohne Artikel, mit Zusatz – und freie Gesuche bleiben frei", function()
    local w = Welt()
    local D = w.ns.Groups.Dungeon
    equal(D("Die Todesminen").name, "Die Todesminen")
    equal(D("todesminen ab Brücke").name, "Die Todesminen")
    equal(D("Scharlachrotes Kloster: Friedhof").min, 28)
    equal(D("Zul'Farrak").max, 54)
    equal(D("Hogger"), nil)
    equal(D("PvP Alterac"), nil)
    equal(D(""), nil)
    equal(D(nil), nil)
end)

test("Passt die Stufe? Grenzen zählen mit", function()
    local w = Welt()
    local G = w.ns.Groups
    local d = G.Dungeon("Die Todesminen")
    check(G.Fits(d, 17) and G.Fits(d, 26), "Grenzen")
    check(not G.Fits(d, 16) and not G.Fits(d, 27), "außerhalb")
    check(not G.Fits(d, nil), "ohne Stufe")
end)

local function Panel(w)
    w:slash("/ea gruppen")
    w.ns.UI:Show("gruppe") -- Gesuch erstellen steht im Unterreiter „Eigene Gruppe“
    return w.ns.UI.panels.gruppen
end

test("Knopf „Dungeons“ öffnet die Liste, ein Klick trägt den Dungeon ein", function()
    local w = Welt()
    local p = Panel(w)
    check(p and p.pick and p.pickMenu, "Knopf oder Liste fehlt")
    check(not p.pickMenu:IsShown(), "Liste ist schon offen")
    p.pick:Click()
    check(p.pickMenu:IsShown(), "Liste öffnet nicht")
    equal(#p.pickMenu.rows, 30)
    local zeile
    for _, row in ipairs(p.pickMenu.rows) do
        if row.dungeon.name == "Gnomeregan" then zeile = row end
    end
    zeile:Click()
    equal(p.what:GetText(), "Gnomeregan")
    check(not p.pickMenu:IsShown(), "Liste bleibt nach der Wahl offen")
    noErrors(w)
end)

test("Liste: zweiter Klick auf den Knopf schließt sie, Reiterwechsel auch", function()
    local w = Welt()
    local p = Panel(w)
    p.pick:Click()
    p.pick:Click()
    check(not p.pickMenu:IsShown(), "zweiter Klick schließt nicht")
    p.pick:Click()
    p.own:Hide()
    check(not p.pickMenu:IsShown(), "bleibt beim Reiterwechsel offen")
    noErrors(w)
end)

test("Freifeld bleibt: „Hogger“ lässt sich weiterhin suchen", function()
    local w = Welt()
    local p = Panel(w)
    p.what:SetText("Hogger")
    p.post:Click()
    local mine = w.ns.Groups:Mine()
    check(mine, "kein Gesuch angelegt")
    equal(mine.what, "Hogger")
    noErrors(w)
end)

test("Gewählter Dungeon wird gesucht wie eingetippt", function()
    local w = Welt()
    local p = Panel(w)
    p.pick:Click()
    p.pickMenu.rows[3]:Click()
    p.post:Click()
    equal(w.ns.Groups:Mine().what, "Die Todesminen")
    noErrors(w)
end)
