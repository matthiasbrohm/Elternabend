-- Gildenbeitritt als Twink (Idee von Phillipp): Der neue Charakter sagt beim Beitritt selbst, ob er neu ist
-- oder ein Twink. Dann meldet er sich nach dem Beitritt seinem Main zu und wird nicht wie ein Neuer begrüßt.

local function Chats(w, prefix)
    for _ = 1, 6 do w:call(w.ns.HardwarePulse) end
    local list = {}
    for _, e in ipairs(w.log) do
        if e.kind == "chat" and e.text:find("^" .. prefix) then list[#list + 1] = e.text end
    end
    return list
end

local function Einladender()
    return login({
        guild = "Elternabend", canInvite = true,
        roster = { { name = "Anna Sturmwind", online = true }, { name = "Beta Lux", online = true } },
    })
end

test("Twink-Anfrage: „ginv twink Greta Glutherz“ wird erkannt, mit und ohne Main", function()
    local w = Einladender()
    local R = w.ns.Recruit
    local ok, twink, main = R:Parse("ginv twink Greta Glutherz")
    check(ok and twink, "nicht als Twink erkannt")
    equal(main, "Greta Glutherz")
    ok, twink, main = R:Parse("ginv twink von Greta Glutherz")
    equal(main, "Greta Glutherz")
    ok, twink, main = R:Parse("Ginv Twink")
    check(ok and twink and main == nil, "„Ginv Twink“")
    ok, twink = R:Parse("ginv bitte")
    check(ok and not twink, "„ginv bitte“ ist kein Twink")
    check(not R:Parse("ginv heute abend"), "Satz als Anfrage erkannt")
    noErrors(w)
end)

test("Twink-Anfrage beim Einladenden: steht als Twink in der Liste, Gilde bekommt Bescheid", function()
    local w = Einladender()
    w:fire("CHAT_MSG_WHISPER", "ginv twink Greta Glutherz", "Clemens Dunkelklinge")
    w:advance(1)
    local q = w.ns.Recruit.queue[1]
    check(q and q.twink, "nicht als Twink in der Warteschlange")
    equal(q.main, "Greta Glutherz")
    seen(w, "comm", "TWK Clemens Dunkelklinge Greta Glutherz")
    check(w.ns.UI.recruitToast and w.ns.UI.recruitToast.name:GetText():find("Twink von Greta Glutherz", 1, true),
        "Fenster nennt den Twink nicht")
    equal(w.ns.db.recruit.log[1].status, "angefragt (Twink)")
    noErrors(w)
end)

test("Beitritt als Twink: zwei Knöpfe, Anfrage mit Main, danach Zuordnung und Zeile im Gildenchat", function()
    local w = login({})
    w.ns.db.myChars[w.ns.NameKey("Greta Glutherz")] = { name = "Greta Glutherz", level = 60, guild = "Elternabend" }
    w.ns.db.myChars[w.ns.NameKey("Kurt Klein")] = { name = "Kurt Klein", level = 10, guild = "Andere Gilde" }
    w:advance(20)
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    check(p.joinBtn:IsShown() and not p.joinTwinkBtn:IsShown(), "vor dem ersten Klick schon zwei Knöpfe")
    w.ns.Join:Click(false)
    w:advance(1)
    check(p.joinTwinkBtn:IsShown(), "Knopf „Ich bin ein Twink“ fehlt")
    equal(p.joinBtn:GetText(), "Ich bin neu")
    check(p.motd:GetText():find("Greta Glutherz", 1, true), p.motd:GetText())
    w:clear()
    w.ns.Join:Click(true)
    w:advance(1)
    seen(w, "chat", "WHISPER Beta Lux ginv twink Greta Glutherz")

    -- Einladung angenommen
    w:clear()
    w.env.IsInGuild = function() return true end
    w.env.GetGuildInfo = function() return "Elternabend", "Twink", 5 end
    w:fire("PLAYER_GUILD_UPDATE")
    w:advance(3)
    seen(w, "comm", "TWK Anna Sturmwind Greta Glutherz")
    seen(w, "comm", "LNK")
    local chats = Chats(w, "GUILD ")
    equal(#chats, 1)
    check(chats[1]:find("ich bin ein neuer Twink von Greta Glutherz", 1, true), chats[1])
    equal(w.ns.db.links[w.ns.NameKey("Anna Sturmwind")].main, "Greta Glutherz")
    -- nur einmal
    w:fire("PLAYER_GUILD_UPDATE")
    w:advance(3)
    equal(#Chats(w, "GUILD "), 1)
    noErrors(w)
end)

test("Beitritt als neuer Spieler: „ginv“ wie bisher, danach schreibt man nichts selbst", function()
    local w = login({})
    w:advance(20)
    w.ns.Join:Click(false)
    w:clear()
    w.ns.Join:Click(false)
    w:advance(1)
    seen(w, "chat", "WHISPER Beta Lux ginv$")
    w:clear()
    w.env.IsInGuild = function() return true end
    w.env.GetGuildInfo = function() return "Elternabend", "Neuling", 5 end
    w:fire("PLAYER_GUILD_UPDATE")
    w:advance(3)
    notSeen(w, "comm", "TWK")
    equal(#Chats(w, "GUILD "), 0)
    noErrors(w)
end)

local function Begruesser()
    local w = login({
        guild = "Elternabend",
        roster = { { name = "Anna Sturmwind", online = true }, { name = "Beta Lux", online = true } },
    })
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    w.ns.SetOpt("welcome", true)
    w:call(w.ns.HardwarePulse)
    return w
end

test("Twinks werden nicht wie neue Spieler begrüßt (Bescheid vom Einladenden)", function()
    local w = Begruesser()
    w:receive("TWK\tClemens Dunkelklinge\tGreta Glutherz", "GUILD", "Beta Lux")
    w:fire("CHAT_MSG_SYSTEM", "Clemens Dunkelklinge ist der Gilde beigetreten.")
    w:advance(60)
    equal(#Chats(w, "GUILD "), 0)
    notSeen(w, "comm", "WELCOME")
    noErrors(w)
end)

test("Twinks werden nicht begrüßt, wenn sie sich gleich selbst als Twink melden", function()
    local w = Begruesser()
    w.env.math = setmetatable({ random = function(a, b) if b then return a end return 0 end }, { __index = math })
    w:fire("CHAT_MSG_SYSTEM", "Clemens Dunkelklinge ist der Gilde beigetreten.")
    w:receive("WELCOME\t" .. w.ns.NameKey("Clemens Dunkelklinge") .. "\t999999", "GUILD", "Beta Lux")
    w:fire("CHAT_MSG_GUILD", "Hallo zusammen, ich bin ein neuer Twink von Greta Glutherz.", "Clemens Dunkelklinge")
    w:advance(200)
    equal(#Chats(w, "GUILD "), 0)
    noErrors(w)
end)
