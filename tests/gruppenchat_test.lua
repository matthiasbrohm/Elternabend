-- Gruppensuche: Stand das Gesuch im Gildenchat, kommt nach Einladungen eine kurze Zeile mit den
-- restlichen Plätzen hinterher – und am Ende „Gruppe ist voll“. Nur mit Häkchen „Auch im Gildenchat posten“.

local function Welt(chat)
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    w:advance(30)
    w.ns.db.groups.chat = chat ~= false
    w:clear()
    return w
end

local function Chats(w)
    -- Nachmeldungen gehen mit der nächsten Eingabe raus: ein paar Tastendrücke nachspielen
    for _ = 1, 4 do w:call(w.ns.HardwarePulse) end
    local list = {}
    for _, e in ipairs(w.log) do
        if e.kind == "chat" and e.text:find("^GUILD ") then table.insert(list, (e.text:gsub("^GUILD ", ""))) end
    end
    return list
end

local function Gesuch(w, tank, heal, dd)
    w:call(w.ns.Groups.Post, w.ns.Groups, "Halle der Thanen", { tank = tank, heal = heal, dd = dd }, "")
    return w.ns.Groups.mine
end

local function Einladen(w, name, role)
    w:call(w.ns.Groups.Invite, w.ns.Groups, { name = name, role = role })
end

test("Gildenchat: nach einer Einladung die restlichen Plätze, am Ende „voll“", function()
    local w = Welt()
    Gesuch(w, 1, 0, 2)
    equal(#Chats(w), 1)
    check(Chats(w)[1]:find("Suche für Halle der Thanen noch 1 Tank, 2 DD", 1, true), Chats(w)[1])
    Einladen(w, "Bert", "dd")
    equal(#Chats(w), 1) -- erst nach kurzer Pause
    w:advance(6)
    equal(#Chats(w), 2)
    equal(Chats(w)[2], "Halle der Thanen: noch 1 Tank und 1 DD gesucht – anflüstern oder /ea gruppen")
    Einladen(w, "Carla", "dd")
    w:advance(6)
    equal(Chats(w)[3], "Halle der Thanen: noch 1 Tank gesucht – anflüstern oder /ea gruppen")
    Einladen(w, "Dora", "tank")
    w:advance(6)
    equal(#Chats(w), 4)
    equal(Chats(w)[4], "Halle der Thanen: Gruppe ist voll, danke!")
    equal(w.ns.Groups.mine, nil)
    noErrors(w)
end)

test("Gildenchat: zwei Einladungen kurz hintereinander ergeben eine Zeile", function()
    local w = Welt()
    Gesuch(w, 1, 1, 3)
    Einladen(w, "Bert", "dd")
    w:advance(2)
    Einladen(w, "Carla", "heal")
    w:advance(6)
    equal(#Chats(w), 2)
    equal(Chats(w)[2], "Halle der Thanen: noch 1 Tank und 2 DD gesucht – anflüstern oder /ea gruppen")
    w:advance(30)
    equal(#Chats(w), 2)
    noErrors(w)
end)

test("Gildenchat: ohne Häkchen keine Nachmeldung", function()
    local w = Welt(false)
    Gesuch(w, 1, 0, 2)
    Einladen(w, "Bert", "dd")
    w:advance(6)
    Einladen(w, "Carla", "dd")
    Einladen(w, "Dora", "tank")
    w:advance(6)
    equal(#Chats(w), 0)
    noErrors(w)
end)

test("Gildenchat: Häkchen nach dem Start abgeschaltet – keine Nachmeldung mehr", function()
    local w = Welt()
    Gesuch(w, 1, 0, 2)
    w.ns.db.groups.chat = false
    Einladen(w, "Bert", "dd")
    w:advance(6)
    equal(#Chats(w), 1)
    noErrors(w)
end)

test("Gildenchat: Plätze per Hand geändert – Zeile nur bei echter Änderung", function()
    local w = Welt()
    Gesuch(w, 1, 1, 2)
    w:call(w.ns.Groups.Post, w.ns.Groups, "Halle der Thanen", { tank = 1, heal = 1, dd = 2 }, "jetzt mit Notiz")
    w:advance(6)
    equal(#Chats(w), 1) -- nur die Notiz geändert
    w:call(w.ns.Groups.Post, w.ns.Groups, "Halle der Thanen", { tank = 1, heal = 0, dd = 2 }, "")
    w:advance(6)
    equal(Chats(w)[2], "Halle der Thanen: noch 1 Tank und 2 DD gesucht – anflüstern oder /ea gruppen")
    -- erst weniger, dann wieder wie zuletzt gemeldet: keine neue Zeile
    w:call(w.ns.Groups.Post, w.ns.Groups, "Halle der Thanen", { tank = 1, heal = 0, dd = 1 }, "")
    w:call(w.ns.Groups.Post, w.ns.Groups, "Halle der Thanen", { tank = 1, heal = 0, dd = 2 }, "")
    w:advance(6)
    equal(#Chats(w), 2)
    noErrors(w)
end)

test("Gildenchat: selbst beendet – keine Zeile hinterher", function()
    local w = Welt()
    Gesuch(w, 1, 0, 2)
    Einladen(w, "Bert", "dd")
    w:call(w.ns.Groups.Close, w.ns.Groups)
    w:advance(6)
    equal(#Chats(w), 1)
    noErrors(w)
end)

test("Gildenchat: Gruppe per Hand voll eingeladen – „voll“ kommt trotzdem", function()
    local w = Welt()
    Gesuch(w, 1, 0, 3)
    w.env.GetNumGroupMembers = function() return 5 end
    w:fire("GROUP_ROSTER_UPDATE")
    w:advance(7)
    equal(w.ns.Groups.mine, nil)
    equal(Chats(w)[#Chats(w)], "Halle der Thanen: Gruppe ist voll, danke!")
    noErrors(w)
end)

test("Gildenchat: Nachmeldung wartet, solange der Chat gesperrt ist", function()
    local w = Welt()
    Gesuch(w, 1, 0, 2)
    w.env.C_ChatInfo.InChatMessagingLockdown = function() return true end
    Einladen(w, "Bert", "dd")
    w:advance(6)
    equal(#Chats(w), 1)
    w.env.C_ChatInfo.InChatMessagingLockdown = function() return false end
    w:fire("ADDON_RESTRICTION_STATE_CHANGED")
    w:advance(2)
    equal(#Chats(w), 2)
    noErrors(w)
end)
