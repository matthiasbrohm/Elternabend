-- Würfelfenster: Bedarf/Gier/Passen und Würfe aus dem Beute-Chat, je Gegenstand übersichtlich.
-- Standardmäßig aus; /ea loot und die eigene Taste öffnen es, wenn es eingeschaltet ist.

local EN = {
    LOOT_ROLL_NEED = "%s has selected Need for: %s",
    LOOT_ROLL_GREED = "%s has selected Greed for: %s",
    LOOT_ROLL_PASSED = "%s passed on: %s",
    LOOT_ROLL_PASSED_AUTO = "%s automatically passed on: %s because he cannot loot that item.",
    LOOT_ROLL_NEED_SELF = "You have selected Need for: %s",
    LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s",
    LOOT_ROLL_PASSED_SELF = "You passed on: %s",
    LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s",
    LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s",
    LOOT_ROLL_WON = "%s won: %s",
    LOOT_ROLL_YOU_WON = "You won: %s",
    LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s",
}
local SCHWERT = "|cff1eff00|Hitem:2000::::::::60:::::::|h[Grünes Schwert]|h|r"
local RING = "|cff0070dd|Hitem:3000::::::::60:::::::|h[Blauer Ring]|h|r"

local function Welt(an)
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    for k, v in pairs(EN) do w.env[k] = v end
    w:advance(30)
    if an ~= false then w.ns.SetOpt("rollWindow", true) end
    w:clear()
    return w
end

local function Chat(w, fmt, ...)
    w:fire("CHAT_MSG_LOOT", string.format(EN[fmt], ...))
end

test("Würfelfenster: standardmäßig aus, /ea loot öffnet dann wie bisher den Plündermeister", function()
    local w = login({ guild = "Elternabend" })
    w:advance(30)
    equal(w.ns.Opt("rollWindow"), false)
    w:slash("/ea loot")
    check(not (w.ns.Rolls.frame and w.ns.Rolls.frame:IsShown()), "Würfelfenster offen, obwohl aus")
    w:slash("/ea würfe")
    seen(w, "print", "Würfelfenster ist aus")
    -- ausgeschaltet wird auch nichts mitgeschrieben
    for k, v in pairs(EN) do w.env[k] = v end
    w:fire("CHAT_MSG_LOOT", "Beta has selected Need for: " .. SCHWERT)
    equal(#w.ns.Rolls:List(), 0)
    noErrors(w)
end)

test("Würfelfenster: eingeschaltet öffnen und schließen /ea loot und die Taste", function()
    local w = Welt()
    w:slash("/ea loot")
    check(w.ns.Rolls.frame:IsShown(), "nicht offen")
    w:slash("/ea loot")
    check(not w.ns.Rolls.frame:IsShown(), "nicht zu")
    w:call(w.ns.Rolls.Toggle, w.ns.Rolls) -- so ruft es die Taste auf
    check(w.ns.Rolls.frame:IsShown(), "Taste öffnet nicht")
    w.ns.SetOpt("rollWindow", false)
    check(not w.ns.Rolls.frame:IsShown(), "beim Ausschalten nicht zu")
    noErrors(w)
end)

test("Würfelfenster: eine Runde mit Bedarf, Gier, Passen, Würfen und Gewinner", function()
    local w = Welt()
    Chat(w, "LOOT_ROLL_NEED", "Beta", SCHWERT)
    Chat(w, "LOOT_ROLL_GREED", "Cora", SCHWERT)
    Chat(w, "LOOT_ROLL_NEED_SELF", SCHWERT)
    Chat(w, "LOOT_ROLL_PASSED_AUTO", "Dirk", SCHWERT)
    Chat(w, "LOOT_ROLL_ROLLED_NEED", 34, SCHWERT, "Beta")
    Chat(w, "LOOT_ROLL_ROLLED_NEED", 87, SCHWERT, w.ns.UnitFullName("player"))
    Chat(w, "LOOT_ROLL_ROLLED_GREED", 99, SCHWERT, "Cora")
    Chat(w, "LOOT_ROLL_YOU_WON", SCHWERT)
    local list = w.ns.Rolls:List()
    equal(#list, 1)
    local r = list[1]
    check(r.done and w.ns.SameName(r.winner, w.ns.UnitFullName("player")), "Gewinner falsch")
    local s = w.ns.Rolls.Sorted(r)
    equal(#s, 4)
    equal(s[1].roll, 87) -- Bedarf, höchster Wurf zuerst
    equal(s[2].name, "Beta")
    equal(s[3].choice, "greed")
    equal(s[4].choice, "pass")
    w.ns.Rolls:Show()
    noErrors(w)
end)

test("Würfelfenster: zwei Gegenstände, alle gepasst, neueste Runde oben", function()
    local w = Welt()
    Chat(w, "LOOT_ROLL_GREED", "Beta", SCHWERT)
    Chat(w, "LOOT_ROLL_PASSED", "Beta", RING)
    Chat(w, "LOOT_ROLL_PASSED_SELF", RING)
    Chat(w, "LOOT_ROLL_ALL_PASSED", RING)
    Chat(w, "LOOT_ROLL_ROLLED_GREED", 12, SCHWERT, "Beta")
    Chat(w, "LOOT_ROLL_WON", "Beta", SCHWERT)
    local list = w.ns.Rolls:List()
    equal(#list, 2)
    check(list[1].link == RING and list[1].allPassed, "Ring: alle gepasst")
    check(list[2].link == SCHWERT and list[2].winner == "Beta", "Schwert: Beta gewinnt")
    noErrors(w)
end)

test("Würfelfenster: zwei gleiche Gegenstände zugleich werden zwei Runden", function()
    local w = Welt()
    Chat(w, "LOOT_ROLL_NEED", "Beta", SCHWERT)
    Chat(w, "LOOT_ROLL_NEED", "Beta", SCHWERT)
    Chat(w, "LOOT_ROLL_GREED", "Cora", SCHWERT)
    equal(#w.ns.Rolls:List(), 2)
    Chat(w, "LOOT_ROLL_WON", "Beta", SCHWERT)
    Chat(w, "LOOT_ROLL_WON", "Cora", SCHWERT)
    local list = w.ns.Rolls:List()
    check(list[1].done and list[2].done, "beide Runden zu Ende")
    noErrors(w)
end)

test("Würfelfenster: nach drei Minuten ist eine Runde vorbei, derselbe Gegenstand beginnt neu", function()
    local w = Welt()
    Chat(w, "LOOT_ROLL_NEED", "Beta", SCHWERT)
    w:advance(200)
    Chat(w, "LOOT_ROLL_NEED", "Beta", SCHWERT)
    equal(#w.ns.Rolls:List(), 2)
    noErrors(w)
end)

test("Würfelfenster: Übersetzungen mit umgestellten Platzhaltern", function()
    local w = Welt()
    local pattern, order = w.ns.Rolls.Compile("Wurf für Bedarf von %3$s für %2$s: %1$d")
    check(pattern, "kein Muster")
    equal(order[1], 3)
    equal(order[2], 2)
    equal(order[3], 1)
    -- Klammern und Punkte im Text stören das Muster nicht
    local p2 = w.ns.Rolls.Compile("%s (Bedarf) für: %s.")
    local a, b = ("Beta (Bedarf) für: x."):match(p2)
    equal(a, "Beta")
    equal(b, "x")
    noErrors(w)
end)

test("Würfelfenster: andere Beutezeilen und geheime Texte werden übergangen", function()
    local w = Welt()
    w:fire("CHAT_MSG_LOOT", "You receive loot: " .. SCHWERT)
    w:fire("CHAT_MSG_LOOT", nil)
    equal(#w.ns.Rolls:List(), 0)
    noErrors(w)
end)

test("Würfelfenster: Leeren und höchstens 40 Runden", function()
    local w = Welt()
    for i = 1, 45 do Chat(w, "LOOT_ROLL_ALL_PASSED", "|cff9d9d9d|Hitem:" .. i .. "::|h[Müll]|h|r") end
    equal(#w.ns.Rolls:List(), 40)
    w.ns.Rolls:Show()
    w:call(w.ns.Rolls.Clear, w.ns.Rolls)
    equal(#w.ns.Rolls:List(), 0)
    noErrors(w)
end)

test("Würfelfenster: Probelauf ohne Gruppe mit den Texten des Spiels", function()
    local w = Welt()
    w:slash("/ea loot test")
    check(w.ns.Rolls.frame:IsShown(), "Fenster nicht offen")
    local list = w.ns.Rolls:List()
    equal(#list, 3)
    seen(w, "print", "Probelauf mit drei Beispiel")
    check(list[3].done and list[3].winner, "erste Runde ohne Gewinner")
    check(list[2].allPassed, "zweite Runde nicht alle gepasst")
    check(not list[1].done and list[1].ends, "dritte Runde läuft nicht")
    equal(#w.ns.Rolls.Sorted(list[3]), 4)
    noErrors(w)
end)

test("Würfelfenster: Probelauf meldet Texte, die das Spiel anders schreibt", function()
    local w = Welt()
    w.env.LOOT_ROLL_ALL_PASSED = false -- gibt es in diesem Spiel nicht
    w:slash("/ea loot test")
    seen(w, "print", "nicht erkannt: LOOT_ROLL_ALL_PASSED")
    noErrors(w)
end)

test("Würfelfenster: Probelauf bei ausgeschaltetem Fenster nur mit Hinweis", function()
    local w = Welt(false)
    w:slash("/ea loot test")
    seen(w, "print", "Würfelfenster ist aus")
    equal(#w.ns.Rolls:List(), 0)
    noErrors(w)
end)

-- Neuere Spielversionen (wie WoW Forever): vorne ein Link auf den Beuteverlauf mit der Rundennummer
local NEU = {}
for k, v in pairs(EN) do NEU[k] = "|HlootHistory:%d|h[Loot]|h: " .. v end

local function WeltNeu()
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    for k, v in pairs(NEU) do w.env[k] = v end
    w:advance(30)
    w.ns.SetOpt("rollWindow", true)
    w:clear()
    return w
end

test("Würfelfenster: Texte mit Beuteverlauf-Link werden erkannt", function()
    local w = WeltNeu()
    local function C(fmt, ...) w:fire("CHAT_MSG_LOOT", string.format(NEU[fmt], ...)) end
    C("LOOT_ROLL_NEED", 7, "Beta", SCHWERT)
    C("LOOT_ROLL_GREED_SELF", 7, SCHWERT)
    C("LOOT_ROLL_ROLLED_NEED", 7, 55, SCHWERT, "Beta")
    C("LOOT_ROLL_WON", 7, "Beta", SCHWERT)
    local list = w.ns.Rolls:List()
    equal(#list, 1)
    equal(list[1].history, 7)
    equal(list[1].winner, "Beta")
    equal(w.ns.Rolls.Sorted(list[1])[1].roll, 55)
    noErrors(w)
end)

test("Würfelfenster: Rundennummer trennt zwei gleiche Gegenstände", function()
    local w = WeltNeu()
    local function C(fmt, ...) w:fire("CHAT_MSG_LOOT", string.format(NEU[fmt], ...)) end
    C("LOOT_ROLL_NEED", 1, "Beta", SCHWERT)
    C("LOOT_ROLL_GREED", 2, "Cora", SCHWERT)
    C("LOOT_ROLL_GREED", 1, "Cora", SCHWERT)
    C("LOOT_ROLL_WON", 2, "Cora", SCHWERT)
    local list = w.ns.Rolls:List()
    equal(#list, 2)
    local eins = list[1].history == 1 and list[1] or list[2]
    equal(#eins.choices, 2)
    check(not eins.done, "Runde 1 ist noch offen")
    noErrors(w)
end)

test("Würfelfenster: Probelauf mit Beuteverlauf-Texten", function()
    local w = WeltNeu()
    w:slash("/ea loot test")
    seen(w, "print", "Probelauf mit drei Beispiel")
    equal(#w.ns.Rolls:List(), 3)
    noErrors(w)
end)

test("Würfelfenster: Symbol des Gegenstands über C_Item, Stern als Bild", function()
    local w = Welt()
    w.env.GetItemIcon = nil
    w.env.C_Item = { GetItemIconByID = function(id) return id == 2000 and 135274 or nil end }
    equal(w.ns.Rolls.ItemIcon(SCHWERT), 135274)
    equal(w.ns.Rolls.ItemIcon("kein Link"), nil)
    Chat(w, "LOOT_ROLL_NEED", "Beta", SCHWERT)
    Chat(w, "LOOT_ROLL_WON", "Beta", SCHWERT)
    w.ns.Rolls:Show()
    local h = w.ns.Rolls.frame.heads[1]
    check(h.state:GetText():find("UI-RaidTargetingIcon_1", 1, true), h.state:GetText())
    check(not h.state:GetText():find("→", 1, true), "Pfeil im Text")
    noErrors(w)
end)
