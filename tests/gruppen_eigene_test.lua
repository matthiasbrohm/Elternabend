-- Eigene Gruppe: laufendes Gesuch im Formular, per Hand Eingeladene belegen gesuchte Plätze

local function Welt()
    local w = login({ guild = "Elternabend", roster = {
        { name = "Beta Lux", online = true, class = "PALADIN" },
        { name = "Greta Glutherz", online = true, class = "PRIEST" },
        { name = "Anna Sturmwind", online = true, class = "MAGE" },
    } })
    w:advance(40)
    return w
end

-- Gruppe aus dem Spieler und den genannten Mitgliedern
local function Gruppe(w, names, roles)
    local env = w.env
    env.IsInGroup = function() return #names > 0 end
    env.GetNumGroupMembers = function() return #names > 0 and #names + 1 or 0 end
    env.UnitExists = function(u)
        if u == "player" then return true end
        local i = tonumber(tostring(u):match("^party(%d)$"))
        return i ~= nil and names[i] ~= nil
    end
    env.UnitName = function(u)
        if u == "player" then return "Anna", "Sturmwind" end
        local i = tonumber(tostring(u):match("^party(%d)$"))
        if i and names[i] then return names[i]:match("^(%S+)%s*(.-)$") end
    end
    env.UnitFullName = env.UnitName
    env.UnitGroupRolesAssigned = function(u)
        local i = tonumber(tostring(u):match("^party(%d)$"))
        return i and roles and roles[i] or "NONE"
    end
end

test("Eigene Gruppe: per Hand eingeladene DDs verringern das Gesuch", function()
    local w = Welt()
    Gruppe(w, { "Beta Lux" }, { "TANK" })
    local G = w.ns.Groups
    check(G:Post("Burg Schattenfang", { tank = 0, heal = 1, dd = 3 }, "", "dd"), "Gesuch nicht gestartet")
    equal(G.mine.target, 6)
    w:clear()
    -- zwei DDs kommen per Hand dazu
    Gruppe(w, { "Beta Lux", "Greta Glutherz", "Clemens Dunkelklinge" }, { "TANK", "DAMAGER", "DAMAGER" })
    w:fire("GROUP_ROSTER_UPDATE")
    w:advance(2)
    equal(G.mine.need.dd, 1)
    equal(G.mine.need.heal, 1)
    seen(w, "print", "gesucht wird noch")
    seen(w, "comm", "LFG .*Burg Schattenfang 0 1 1")
    -- ohne gesetzte Rolle: erst DD, dann Heiler
    Gruppe(w, { "Beta Lux", "Greta Glutherz", "Clemens Dunkelklinge", "Mira Mondschein" }, { "TANK", "DAMAGER", "DAMAGER" })
    w:fire("GROUP_ROSTER_UPDATE")
    w:advance(2)
    equal(G.mine.need.dd, 0)
    equal(G.mine.need.heal, 1)
    noErrors(w)
end)

test("Eigene Gruppe: Formular zeigt das laufende Gesuch und lässt es ändern", function()
    local w = Welt()
    local G = w.ns.Groups
    G:Post("Burg Schattenfang", { tank = 0, heal = 0, dd = 3 }, "gemütlich", "heal")
    w.ns.UI:Show("gruppe")
    local p = w.ns.UI.panels.gruppen
    -- Formular zurücksetzen wie nach neu laden
    p.need = { tank = 1, heal = 1, dd = 3 }
    p.what:SetText("")
    p.syncedKey = nil
    w:call(p.Refresh, p)
    equal(p.what:GetText(), "Burg Schattenfang")
    equal(p.note:GetText(), "gemütlich")
    equal(p.need.tank, 0)
    equal(p.need.dd, 3)
    equal(p.post:GetText(), "Aktualisieren")
    -- einen DD weniger und aktualisieren
    w:call(p.needButtons.dd:GetScript("OnClick"), p.needButtons.dd, "RightButton")
    equal(p.need.dd, 2)
    w:call(p.Refresh, p)
    equal(p.need.dd, 2) -- eigene Änderung bleibt stehen
    w:call(p.post:GetScript("OnClick"))
    equal(G.mine.need.dd, 2)
    equal(G.mine.what, "Burg Schattenfang")
    noErrors(w)
end)
