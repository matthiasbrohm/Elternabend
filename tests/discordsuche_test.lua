-- Suchen aus Discord und Dungeonfinder im Reiter „Gruppen“ (über die Mac-App)

local function Text(now)
    return "#ELTERNABEND-GRUPPEN;1;" .. now .. "\n"
        .. "gruppe;ab12;Die Todesminen;" .. (now + 3600) .. ";60;Condor;0;1;2;gemütlich;discord\n"
        .. "gruppe;cd34;Halle der Thanen;" .. (now + 600) .. ";30;Beta Lux🌒;1;0;0;;web\n"
end

local function Welt(app)
    local w = world({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true }, { name = "Beta Lux", online = true } } })
    if app then w.env.ElternabendAbgleich = { v = 1, gruppen = Text(w.env.time()) } end
    w:fire("ADDON_LOADED", "Elternabend")
    w:fire("PLAYER_LOGIN")
    w:fire("PLAYER_ENTERING_WORLD", true, false)
    w:fire("GUILD_ROSTER_UPDATE")
    w:advance(40)
    return w
end

test("Discord-Suchen: aus der Datei der Mac-App gelesen, nach Startzeit", function()
    local w = Welt(true)
    local list = w.ns.WebGroups:Active()
    equal(#list, 2)
    equal(list[1].what, "Halle der Thanen")
    equal(list[1].by, "Beta Lux") -- Emoji entfernt
    equal(list[2].need.heal, 1)
    equal(list[2].note, "gemütlich")
    check(w.ns.WebGroups.When(list[1]):find("^heute ") or w.ns.WebGroups.When(list[1]):find("^morgen "), w.ns.WebGroups.When(list[1]))
    noErrors(w)
end)

test("Discord-Suchen: werden an die Gilde weitergegeben und bei anderen angezeigt", function()
    local w = Welt(true)
    seen(w, "comm", "LFGWEB %d+ ab12 Die Todesminen")
    -- ein anderer ohne App bekommt sie
    local w2 = Welt(false)
    equal(#w2.ns.WebGroups:Active(), 0)
    local now = w2.env.time()
    w2:receive(table.concat({ "LFGWEB", now, "ab12", "Die Todesminen", now + 3600, 60, "Condor", 0, 1, 2, "gemütlich" }, "\t"), "GUILD", "Beta Lux")
    equal(#w2.ns.WebGroups:Active(), 1)
    -- nur von Gildenmitgliedern
    w2:receive(table.concat({ "LFGWEB", now, "zz", "Fremd", now + 3600, 60, "X", 1, 0, 0, "" }, "\t"), "GUILD", "Fremder Gast")
    equal(#w2.ns.WebGroups:Active(), 1)
    -- im Reiter „Gruppen“ als eigene Zeile
    w2.ns.UI:Show("gruppen")
    local p = w2.ns.UI.panels.gruppen
    w2:call(p.Refresh, p)
    check(not p.empty:IsShown(), "Hinweis „niemand sucht“ trotz Discord-Suche")
    noErrors(w)
    noErrors(w2)
end)

test("Discord-Suchen: wer neu einloggt, bekommt sie auf Nachfrage", function()
    local w = Welt(true)
    w:clear()
    w:receive("LFGQ", "GUILD", "Beta Lux")
    w:advance(8)
    seen(w, "comm", "LFGWEB")
    noErrors(w)
end)

test("Discord-Suchen: 30 Minuten nach dem Start und bei altem Stand weg", function()
    local w = Welt(false)
    local now = w.env.time()
    w:receive(table.concat({ "LFGWEB", now, "a", "Alt", now - 40 * 60, 60, "X", 1, 0, 0, "" }, "\t"), "GUILD", "Beta Lux")
    w:receive(table.concat({ "LFGWEB", now - 7 * 3600, "b", "Uralt", now + 600, 60, "X", 1, 0, 0, "" }, "\t"), "GUILD", "Beta Lux")
    w:receive(table.concat({ "LFGWEB", now, "c", "Läuft", now - 10 * 60, 60, "X", 1, 0, 0, "" }, "\t"), "GUILD", "Beta Lux")
    local list = w.ns.WebGroups:Active()
    equal(#list, 1)
    equal(list[1].what, "Läuft")
    equal(w.ns.WebGroups.When(list[1]), "läuft seit 10 Min.")
    noErrors(w)
end)

test("Discord-Suchen: neuerer Stand ersetzt älteren, älterer nicht den neueren", function()
    local w = Welt(false)
    local now = w.env.time()
    w:receive(table.concat({ "LFGWEB", now, "a", "Neu", now + 600, 60, "X", 0, 0, 1, "" }, "\t"), "GUILD", "Beta Lux")
    w:receive(table.concat({ "LFGWEB", now - 600, "a", "Alt", now + 600, 60, "X", 1, 1, 3, "" }, "\t"), "GUILD", "Beta Lux")
    equal(w.ns.WebGroups:Active()[1].what, "Neu")
    noErrors(w)
end)

test("Discord-Suchen: ohne Mac-App und ohne Meldungen bleibt alles wie bisher", function()
    local w = Welt(false)
    equal(#w.ns.WebGroups:Active(), 0)
    notSeen(w, "comm", "LFGWEB")
    noErrors(w)
end)

test("Discord-Suchen: Zeile im Reiter „Gruppen“ mit Tooltip und Hinweis beim Klick", function()
    local w = Welt(true)
    w.ns.UI:Show("gruppen")
    local p = w.ns.UI.panels.gruppen
    w:call(p.Refresh, p)
    local e = w.ns.WebGroups:Active()[1]
    check(e.web, "nicht als Discord-Suche markiert")
    w:clear()
    check(p.list, "Liste fehlt")
    w:call(p.list.onEnter, w.env.UIParent, e)
    w:call(p.list.onClick, nil, e, "LeftButton")
    seen(w, "print", "melden kannst du dich im Discord")
    noErrors(w)
end)

test("Discord-Suchen: Quelle Webseite kommt bei den anderen an", function()
    local w = Welt(true)
    seen(w, "comm", "LFGWEB %d+ cd34 Halle der Thanen .* web$")
    noErrors(w)
end)

test("Discord-Suchen: Startzeit steht in der Spalte „Status“ (nicht abgeschnitten)", function()
    local w = Welt(true)
    w.ns.UI:Show("gruppen")
    local p = w.ns.UI.panels.gruppen
    w:call(p.Refresh, p)
    local found
    for _, f in ipairs(w.frames) do
        local t = f.GetText and f:GetText()
        if type(t) == "string" and t:find("Discord|r", 1, true) and (t:find("heute ", 1, true) or t:find("morgen ", 1, true)) then found = t end
    end
    check(found, "Zeit nicht in der Statusspalte")
    noErrors(w)
end)
