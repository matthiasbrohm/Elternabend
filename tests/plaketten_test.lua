-- Plaketten in drei Farben: rot = Gruppensuche, gelb = Pinnwand, grün = neuer Herstellungsauftrag.
-- An der Minimap an drei Ecken, damit mehrere gleichzeitig zu sehen sind.

local function Welt()
    local w = login({ guild = "Elternabend", roster = {
        { name = "Anna Sturmwind", online = true },
        { name = "Beta Lux", online = true, classFile = "PRIEST" },
    } })
    w:advance(30)
    w:clear()
    return w, w.ns.UI.minimapButton
end

local function Zahl(badge)
    return badge:IsShown() and badge.text:GetText() or nil
end

local function Auftrag(w, id)
    w:receive("ORDER\t" .. id .. "\t2580\tAnna Sturmwind\t", "WHISPER", "Beta Lux")
    w:advance(2)
end

test("Plaketten: die drei Sorten haben ihre Farbe", function()
    local w, mm = Welt()
    equal(mm.badge.color, "rot")
    equal(mm.badgeBoard.color, "gelb")
    equal(mm.badgeOrders.color, "gruen")
    equal(w.ns.UI.tabs.gruppen.badge.color, "rot")
    equal(w.ns.UI.tabs.pinnwand.badge.color, "gelb")
    equal(w.ns.UI.tabs.berufe.badge.color, "gruen")
    noErrors(w)
end)

test("Plaketten: neuer Auftrag – grün an Minimap und Reiter „Berufe“, bis er beantwortet ist", function()
    local w, mm = Welt()
    equal(Zahl(mm.badgeOrders), nil)
    Auftrag(w, "a1")
    equal(Zahl(mm.badgeOrders), "1")
    equal(Zahl(w.ns.UI.tabs.berufe.badge), "1")
    Auftrag(w, "a2")
    equal(Zahl(mm.badgeOrders), "2")
    -- im Reiter „Berufe“ selbst keine Plakette am Reiter, an der Minimap bleibt sie
    w.ns.UI:Show("berufe")
    equal(Zahl(w.ns.UI.tabs.berufe.badge), nil)
    equal(Zahl(mm.badgeOrders), "2")
    -- angenommen und abgelehnt: nicht mehr neu
    w:call(w.ns.Orders.SetState, w.ns.Orders, "a1", "angenommen")
    w:call(w.ns.Orders.SetState, w.ns.Orders, "a2", "abgelehnt")
    w:advance(1)
    equal(Zahl(mm.badgeOrders), nil)
    noErrors(w)
end)

test("Plaketten: Auftrag und Gruppensuche gleichzeitig – zwei Plaketten an verschiedenen Ecken", function()
    local w, mm = Welt()
    Auftrag(w, "a1")
    w.ns.Groups.UnseenCount = function() return 1 end
    w:call(w.ns.UI.UpdateBadges, w.ns.UI)
    equal(Zahl(mm.badge), "1")
    equal(Zahl(mm.badgeOrders), "1")
    check(mm.badge ~= mm.badgeOrders and mm.badge:IsShown() and mm.badgeOrders:IsShown(), "beide Plaketten sichtbar")
    noErrors(w)
end)

test("Plaketten: neuer Zettel – gelb an der Minimap, im Reiter „Pinnwand“ nicht", function()
    local w, mm = Welt()
    w.ns.Board.UnreadCount = function() return 3 end
    w:call(w.ns.UI.UpdateBadges, w.ns.UI)
    equal(Zahl(mm.badgeBoard), "3")
    equal(Zahl(w.ns.UI.tabs.pinnwand.badge), "3")
    w.ns.UI:Show("pinnwand")
    w:call(w.ns.UI.UpdateBadges, w.ns.UI)
    equal(Zahl(mm.badgeBoard), nil)
    equal(Zahl(w.ns.UI.tabs.pinnwand.badge), nil)
    noErrors(w)
end)

test("Plaketten: Startseite nennt neue Aufträge", function()
    local w = Welt()
    Auftrag(w, "a1")
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    w:call(p.Refresh, p)
    check((p.now.orders.extra:GetText() or ""):find("1 neuer Auftrag", 1, true), tostring(p.now.orders.extra:GetText()))
    noErrors(w)
end)

test("Plaketten: ohne Gilde keine Auftrags-Plakette", function()
    local w = login({})
    w:advance(30)
    equal(w.ns.Orders:NewCount(), 0)
    noErrors(w)
end)
