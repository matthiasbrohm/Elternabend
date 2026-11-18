-- Leitung » Chronik: Klick auf einen Eintrag öffnet das Flüsterfenster (z. B. nach einem Austritt nachfragen),
-- Rechtsklick auf Jubiläum oder Stufe 60 schlägt den Glückwunsch für den Gildenchat vor.

local function Welt()
    local w = login({ guild = "Elternabend", officer = true, rank = "Gildenleitung", rankIndex = 0,
        roster = { { name = "Anna Sturmwind", online = true } } })
    w:advance(30)
    w.tells = {}
    w.env.ChatFrame_SendTell = function(name) table.insert(w.tells, name) end
    w.dialoge = {}
    w.ns.UI.TextDialog = function(_, titel, _, text) table.insert(w.dialoge, { titel = titel, text = text }) end
    w.ns.UI:Show("leitung")
    w:clear()
    return w, w.ns.UI.panels.leitung.chronik
end

test("Chronik: Klick auf einen Austritt öffnet das Flüsterfenster", function()
    local w, list = Welt()
    local e = { t = w.env.time(), type = "leave", name = "Dealla Südwind-Forever", how = "quit" }
    w:call(list.onClick, {}, e, "LeftButton")
    equal(#w.tells, 1)
    equal(w.tells[1], "Dealla Südwind-Forever")
    equal(#w.dialoge, 0)
    w:call(list.onClick, {}, e, "RightButton") -- kein Glückwunsch für einen Austritt
    equal(#w.tells, 1)
    equal(#w.dialoge, 0)
    noErrors(w)
end)

test("Chronik: Rechtsklick auf Stufe 60 schlägt den Glückwunsch vor, Klick flüstert", function()
    local w, list = Welt()
    local m = w.ns.Members:Find("Anna Sturmwind")
    check(m, "Anna fehlt in der Gildenliste")
    local e = { t = w.env.time(), type = "level", name = m.name, class = "WARRIOR" }
    w:call(list.onClick, {}, e, "RightButton")
    equal(#w.dialoge, 1)
    check(w.dialoge[1].text:find("Glückwunsch zu Stufe 60, Anna!", 1, true), w.dialoge[1].text)
    equal(#w.tells, 0)
    w:call(list.onClick, {}, e, "LeftButton")
    equal(#w.tells, 1)
    equal(#w.dialoge, 1)
    noErrors(w)
end)

test("Chronik: Tooltip nennt Klick und Rechtsklick", function()
    local w, list = Welt()
    local m = w.ns.Members:Find("Anna Sturmwind")
    local lines = {}
    w.env.GameTooltip.AddLine = function(_, text) table.insert(lines, text) end
    w:call(list.onEnter, w.env.CreateFrame("Frame"), { t = w.env.time(), type = "level", name = m.name, class = "WARRIOR" })
    local alle = table.concat(lines, "\n")
    check(alle:find("Klick: anflüstern", 1, true), alle)
    check(alle:find("Rechtsklick: im Gildenchat gratulieren", 1, true), alle)
    lines = {}
    w:call(list.onEnter, w.env.CreateFrame("Frame"), { t = w.env.time(), type = "leave", name = "Weg Gegangen", how = "quit" })
    alle = table.concat(lines, "\n")
    check(alle:find("nur, wenn er oder sie gerade online ist", 1, true), alle)
    noErrors(w)
end)
