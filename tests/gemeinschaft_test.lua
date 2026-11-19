-- 4.26: Stufenaufstiege, Begrüßung neuer Mitglieder, Stufe-60-Prognose, Gildenkarte, Nachricht des Tages ändern

local function Gilde(extra)
    local roster = {
        { name = "Anna Sturmwind", online = true, level = 19, classFile = "PRIEST" },
        { name = "Beta Lux", online = true, level = 30, classFile = "MAGE" },
        { name = "Cora Kiesel", online = false, level = 44 },
    }
    local opts = { guild = "Elternabend", roster = roster }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    w:advance(30)
    w:clear()
    w.roster = roster
    return w
end

local function Roster(w)
    w:fire("GUILD_ROSTER_UPDATE")
    w:advance(5)
end

local function GuildChats(w)
    for _ = 1, 6 do w:call(w.ns.HardwarePulse) end
    local list = {}
    for _, e in ipairs(w.log) do
        if e.kind == "chat" and e.text:find("^GUILD ") then list[#list + 1] = (e.text:gsub("^GUILD ", "")) end
    end
    return list
end

-- Stufenaufstiege ------------------------------------------------------------------------------
test("Stufenaufstiege: Aufstieg in der Gildenliste wird bemerkt und steht auf der Startseite", function()
    local w = Gilde()
    equal(#w.ns.Leveling:Ups(), 0) -- erster Stand: nur merken
    w.roster[1].level = 20
    Roster(w)
    local ups = w.ns.Leveling:Ups()
    equal(#ups, 1)
    equal(ups[1].from, 19)
    equal(ups[1].to, 20)
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    w:call(p.Refresh, p)
    local text = p.now.levelups.text:GetText()
    check(text:find("Anna Sturmwind", 1, true) and text:find("20", 1, true), text)
    check(p.now.levelups.extra:GetText():find("1 in den letzten 24 Std.", 1, true), p.now.levelups.extra:GetText())
    noErrors(w)
end)

test("Stufenaufstiege: neueste zuerst, „Alle“ zeigt die Liste", function()
    local w = Gilde()
    w.roster[1].level = 20
    Roster(w)
    w.roster[2].level = 31
    Roster(w)
    local ups = w.ns.Leveling:Ups()
    equal(ups[1].name, "Beta Lux")
    local shown
    w.ns.UI.TextDialog = function(_, title, _, text) shown = { title = title, text = text } end
    w:call(w.ns.UI.ShowLevelUps, w.ns.UI)
    check(shown and shown.text:find("Beta Lux  30 » 31", 1, true), shown and shown.text)
    noErrors(w)
end)

test("Stufenaufstiege: halbe Gildenliste beim Einloggen führt zu nichts", function()
    local w = Gilde()
    for i = 1, 20 do table.insert(w.roster, { name = "Extra" .. i, level = 10 }) end
    Roster(w)
    for i = 1, 23 do w.roster[i] = nil end
    w.roster[1] = { name = "Anna Sturmwind", online = true, level = 25 }
    Roster(w)
    equal(#w.ns.Leveling:Ups(), 0)
    noErrors(w)
end)

-- Begrüßung ------------------------------------------------------------------------------------
local function Beitritt(w, name)
    w:fire("CHAT_MSG_SYSTEM", string.format(w.env.ERR_GUILD_JOIN_S, name))
end

test("Begrüßung: standardmäßig aus – kein Wort im Chat", function()
    local w = Gilde()
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    equal(w.ns.Opt("welcome"), false)
    w:call(w.ns.HardwarePulse)
    Beitritt(w, "Dealla Südwind")
    w:advance(40)
    equal(#GuildChats(w), 0)
    noErrors(w)
end)

test("Begrüßung: allein mit dem Schalter schreibt man die lange Begrüßung", function()
    local w = Gilde()
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    w.ns.SetOpt("welcome", true)
    w:call(w.ns.HardwarePulse) -- man spielt gerade
    Beitritt(w, "Dealla Südwind")
    w:advance(4)
    seen(w, "comm", "WELCOME")
    local chats = GuildChats(w)
    equal(#chats, 1)
    check(chats[1] == "Willkommen bei Elternabend, Dealla Südwind. Stell dich gern kurz im Discord in #vorstellungsrunde vor: discord.gg/elternabend - Tipp: Unser Addon \"Elternabend\" (CurseForge/Wago) zeigt Raids, Berufe und Gruppen.", chats[1])
    check(chats[1]:find("#vorstellungsrunde", 1, true) and #chats[1] <= 255, chats[1])
    w:advance(60)
    equal(#GuildChats(w), 1)
    noErrors(w)
end)

test("Begrüßung: wer die niedrigere Zahl hat, schreibt nach der langen nur kurz", function()
    local w = Gilde()
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    w.ns.SetOpt("welcome", true)
    w.env.math = setmetatable({ random = function(a, b) if b then return a end return 0 end }, { __index = math })
    w:call(w.ns.HardwarePulse)
    Beitritt(w, "Dealla Südwind")
    w:receive("WELCOME\tdealla südwind\t999999", "GUILD", "Beta Lux")
    w:receive("WELCOME\t" .. w.ns.NameKey("Dealla Südwind") .. "\t999999", "GUILD", "Beta Lux")
    w:advance(4)
    equal(#GuildChats(w), 0) -- Beta hat gewonnen: erst die lange abwarten
    w:fire("CHAT_MSG_GUILD", "Herzlich willkommen bei Elternabend, Dealla Südwind! … discord.gg/elternabend …", "Beta Lux")
    w:advance(15)
    local chats = GuildChats(w)
    equal(#chats, 1)
    check(not chats[1]:find("discord", 1, true) and chats[1]:find("Dealla", 1, true), chats[1])
    noErrors(w)
end)

test("Begrüßung: bleibt die lange aus, schreibt sie der Nächste", function()
    local w = Gilde()
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    w.ns.SetOpt("welcome", true)
    w.env.math = setmetatable({ random = function(a, b) if b then return a end return 0 end }, { __index = math })
    w:call(w.ns.HardwarePulse)
    Beitritt(w, "Dealla Südwind")
    w:receive("WELCOME\t" .. w.ns.NameKey("Dealla Südwind") .. "\t999999", "GUILD", "Beta Lux")
    w:advance(35)
    local chats = GuildChats(w)
    equal(#chats, 1)
    check(chats[1]:find("#vorstellungsrunde", 1, true), chats[1])
    noErrors(w)
end)

test("Begrüßung: wer länger nicht an der Tastatur war, lost nicht mit und schreibt kurz", function()
    local w = Gilde()
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    w.ns.SetOpt("welcome", true)
    w:call(w.ns.HardwarePulse)
    w:advance(200)
    w:clear()
    Beitritt(w, "Dealla Südwind")
    notSeen(w, "comm", "WELCOME")
    noErrors(w)
end)

-- Prognose -------------------------------------------------------------------------------------
test("Prognose: erst nach einer Stunde Spielzeit, dann mit Datum", function()
    local w = Gilde()
    local level, xp = 30, 0
    w.env.UnitLevel = function() return level end
    w.env.UnitXP = function() return xp end
    w.env.UnitIsAFK = function() return false end
    equal(w.ns.Leveling.TotalXP(60, 0), 4084700)
    check(w.ns.Leveling:ForecastText():find("nach etwa einer Stunde", 1, true), w.ns.Leveling:ForecastText())
    for _ = 1, 90 do
        xp = xp + 400 -- 24.000 Erfahrung pro Stunde
        w:call(w.ns.Leveling.Tick, w.ns.Leveling, 60)
    end
    local f = w.ns.Leveling:Forecast()
    check(f and f.rate and math.abs(f.rate - 24000) < 600, "Rate: " .. tostring(f and f.rate))
    local text = w.ns.Leveling:ForecastText()
    check(text:find("Stufe 60 bei deinem Tempo etwa am", 1, true), text)
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    w:call(p.Refresh, p)
    equal(p.forecast:GetText(), text)
    noErrors(w)
end)

test("Prognose: AFK zählt nicht, auf Stufe 60 keine Zeile", function()
    local w = Gilde()
    w.env.UnitLevel = function() return 30 end
    w.env.UnitXP = function() return 0 end
    w.env.UnitIsAFK = function() return true end
    for _ = 1, 90 do w:call(w.ns.Leveling.Tick, w.ns.Leveling, 60) end
    check(w.ns.Leveling:Forecast().wait, "AFK wurde gezählt")
    w.env.UnitLevel = function() return 60 end
    equal(w.ns.Leveling:ForecastText(), "")
    noErrors(w)
end)

-- Gildenkarte ----------------------------------------------------------------------------------
local function Karte(w)
    w.env.C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
        GetWorldPosFromMapPos = function() return 0, { x = -9000.5, y = 300.4 } end,
        GetMapPosFromWorldPos = function(_, pos) return 1429, { x = 0.4, y = 0.6 } end,
    }
    w.env.CreateVector2D = function(x, y) return { x = x, y = y } end
end

test("Gildenkarte: standardmäßig aus, nichts wird gesendet", function()
    local w = Gilde()
    Karte(w)
    w:advance(70)
    notSeen(w, "comm", "POS")
    equal(w.ns.Opt("guildMap"), false)
    noErrors(w)
end)

test("Gildenkarte: eingeschaltet wird der Standort geteilt, ausgeschaltet zurückgenommen", function()
    local w = Gilde()
    Karte(w)
    w.ns.SetOpt("guildMap", true)
    w:advance(2)
    seen(w, "comm", "POS 0 %-9000%.5 300%.4")
    w:clear()
    w.ns.SetOpt("guildMap", false)
    w:advance(2)
    seen(w, "comm", "POS off")
    noErrors(w)
end)

test("Gildenkarte: in Dungeons wird nichts gesendet", function()
    local w = Gilde()
    Karte(w)
    w.env.IsInInstance = function() return true, "party" end
    w.ns.SetOpt("guildMap", true)
    w:advance(70)
    notSeen(w, "comm", "POS 0")
    noErrors(w)
end)

test("Gildenkarte: Standort anderer wird gemerkt und nach einer Weile vergessen", function()
    local w = Gilde()
    Karte(w)
    w.ns.SetOpt("guildMap", true)
    w:receive("POS\t0\t-8800\t500\t31\tMAGE", "GUILD", "Beta Lux")
    local peer = w.ns.GuildMap.peers[w.ns.NameKey("Beta Lux")]
    check(peer and peer.level == 31 and peer.class == "MAGE", "nicht gemerkt")
    w:receive("POS\t0\t-8800\t500\t31\tMAGE", "GUILD", "Fremder Gast") -- nicht in der Gilde
    check(not w.ns.GuildMap.peers[w.ns.NameKey("Fremder Gast")], "Fremder gemerkt")
    w:receive("POS\toff", "GUILD", "Beta Lux")
    check(not w.ns.GuildMap.peers[w.ns.NameKey("Beta Lux")], "off nicht verarbeitet")
    noErrors(w)
end)

-- Nachricht des Tages ---------------------------------------------------------------------------
test("Nachricht des Tages: „Ändern“ nur für wen es darf, Speichern läuft über /gmotd", function()
    local w = Gilde()
    local set
    w.env.C_GuildInfo.CanEditMOTD = function() return false end
    w.env.C_GuildInfo.SetMOTD = function(text) set = text end -- gesperrt: darf nie aufgerufen werden
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    w:call(p.Refresh, p)
    check(not p.motdEdit:IsShown(), "Knopf für alle sichtbar")
    w.env.C_GuildInfo.CanEditMOTD = function() return true end
    w:call(p.Refresh, p)
    check(p.motdEdit:IsShown(), "Knopf fehlt für die Leitung")
    -- Attribute der Knöpfe merken (die Testwelt kennt sie sonst nicht)
    local attrs = {}
    w.env.SecureAttr = attrs
    local create = w.env.CreateFrame
    w.env.CreateFrame = function(kind, name, parent, template, ...)
        local f = create(kind, name, parent, template, ...)
        if template == "SecureActionButtonTemplate" then
            rawset(f, "SetAttribute", function(self, k, v) attrs[k] = v end)
            rawset(f, "GetAttribute", function(self, k) return attrs[k] end)
        end
        return f
    end
    w.env.SLASH_GUILD_MOTD1 = "/gndt"
    w:call(w.ns.UI.EditMOTD, w.ns.UI)
    local d = w.ns.UI.motdDialog
    check(d:IsShown() and d.secure:IsShown(), "Fenster oder sicherer Knopf fehlt")
    d.edit:SetText(string.rep("ä", 100) .. "\n/run print(1)")
    d.Update()
    local macro = d.secure:GetAttribute("macrotext")
    check(macro:find("^/gndt ") and not macro:find("\n"), macro) -- der Befehl des deutschen Spiels
    check(#macro <= 6 + 128 and not macro:find("[\192-\255]$"), "nicht sauber gekürzt")
    equal(set, nil)
    -- Kampf: Fenster und sicherer Knopf verschwinden
    w:fire("PLAYER_REGEN_DISABLED")
    check(not d:IsShown() and not d.secure:IsShown(), "im Kampf noch offen")
    noErrors(w)
end)

-- Senden, wenn das Spiel blockiert ---------------------------------------------------------------
test("Chat: blockiert das Spiel einmal, geht die Nachricht mit der nächsten Eingabe noch einmal raus", function()
    local w = Gilde()
    local blocked = true
    w.env.C_ChatInfo.SendChatMessage = function(text, channel)
        if blocked then
            w:fire("ADDON_ACTION_BLOCKED", "Elternabend", "C_ChatInfo.SendChatMessage()")
            return
        end
        table.insert(w.log, { kind = "chat", text = channel .. " " .. text })
    end
    w:call(w.ns.SendChat, "Hallo Gilde", "GUILD")
    equal(w.ns.db.settings.chatNeedsInput, true)
    equal(w.ns.PendingInput(), 1)
    blocked = false
    local chats = GuildChats(w)
    equal(#chats, 1)
    equal(chats[1], "Hallo Gilde")
    -- ab jetzt gleich mit der nächsten Eingabe
    w:call(w.ns.SendChat, "Zweite", "GUILD")
    equal(w.ns.PendingInput(), 1)
    equal(GuildChats(w)[2], "Zweite")
    noErrors(w)
end)

test("Chat: ohne Blockade direkt gesendet", function()
    local w = Gilde()
    w:call(w.ns.SendChat, "Direkt", "GUILD")
    equal(w.ns.PendingInput(), 0)
    seen(w, "chat", "^GUILD Direkt$")
    noErrors(w)
end)

test("Nachricht des Tages: ohne Befehl im Spiel /gmotd", function()
    local w = Gilde()
    w.env.SLASH_GUILD_MOTD1 = false
    equal(w.ns.UI.MOTDCommand(), "/gmotd")
    w.env.SLASH_GUILD_MOTD1 = "/gmotd"
    equal(w.ns.UI.MOTDCommand(), "/gmotd")
    noErrors(w)
end)

test("Gildenkarte: wer mit in der Gruppe ist, bekommt keinen zweiten Punkt", function()
    local w = Gilde()
    Karte(w)
    w.ns.SetOpt("guildMap", true)
    w:receive("POS\t0\t-8800\t500\t31\tMAGE", "GUILD", "Beta Lux")
    w.env.IsInGroup = function() return true end
    w.env.IsInRaid = function() return false end
    w.env.UnitExists = function(unit) return unit == "party1" end
    w.env.UnitName = function(unit) if unit == "party1" then return "Beta", "Lux" end return "Anna", "Sturmwind" end
    check(w.ns.GuildMap.InMyGroup("Beta Lux"), "Gruppenmitglied nicht erkannt")
    check(not w.ns.GuildMap.InMyGroup("Cora Kiesel"), "Fremde als Gruppe erkannt")
    w.env.IsInGroup = function() return false end
    check(not w.ns.GuildMap.InMyGroup("Beta Lux"), "ohne Gruppe erkannt")
    noErrors(w)
end)

test("Prognose: geheime Werte (Sperren im Kampf) führen nicht zu Fehlern", function()
    local w = Gilde()
    local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    w.env.issecretvalue = function(v) return v == SECRET end
    w.env.UnitLevel = function() return 30 end
    w.env.UnitXP = function() return 1000 end
    w.env.UnitIsAFK = function() return SECRET end
    w:call(w.ns.Leveling.Tick, w.ns.Leveling, 60) -- AFK unbekannt: die Minute zählt
    w.env.UnitLevel = function() return SECRET end
    w:call(w.ns.Leveling.Tick, w.ns.Leveling, 60) -- Stufe unbekannt: nichts tun
    equal(w.ns.Leveling:Forecast(), nil)
    equal(w.ns.Leveling:ForecastText(), "")
    noErrors(w)
end)
