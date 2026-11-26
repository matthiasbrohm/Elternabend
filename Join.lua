-- Elternabend: „Der Gilde beitreten“ per Knopf
--
-- Wer noch nicht in der Gilde ist, erreicht den Gildenkanal des Addons nicht. Deshalb
-- sitzen Einladende (alle, die einladen dürfen) im Hintergrund in einem versteckten
-- Chat-Kanal; darüber gehen nur Beitrittsanfragen, im Chat sieht man ihn nicht.
-- Wer anfragt, tritt dem Kanal erst mit dem Klick auf „Der Gilde beitreten“ bei und
-- verlässt ihn kurz danach wieder – Charaktere ohne Gilde sitzen nicht dauerhaft darin.
-- Die Anfrage landet bei den Einladenden im bekannten Gildenanfrage-Fenster;
-- eingeladen wird weiterhin per Klick (WoW erlaubt es nicht ohne).
--
-- In WoW Forever kommen Addon-Nachrichten über den Kanal von Nicht-Mitgliedern nicht an
-- (getestet am 05.11.2026). Deshalb flüstert der Knopf zusätzlich ganz normal „ginv“ an
-- alle aus INVITERS – das landet bei ihnen in der Gildenanfrage wie ein getipptes „ginv“.
-- Wer gerade offline ist, bekommt nichts; die Meldung „Kein Spieler namens …“ wird
-- ausgeblendet und gezählt.
--
-- Twinks: Nach dem ersten Klick wählt man „Ich bin neu“ oder „Ich bin ein Twink“ (Idee von Phillipp).
-- Ein Twink schickt „ginv twink <Main>“ statt „ginv“. Den Main kennt das Addon aus den eigenen Charakteren
-- (accountweit gespeichert: wer schon in der Gilde ist). Nach dem Beitritt meldet sich der Twink selbst:
-- Zuordnung zum Main für alle und eine Zeile im Gildenchat – und die Begrüßung für Neue bleibt aus.
--
--   JOINREQ            Anfragender → Kanal
--   JOINACK            Einladender → Anfragender (Flüstern): „Anfrage ist angekommen“
--   JOINDONE \t Name    Einladender → Kanal: erledigt, bei den anderen entfernen
local _, ns = ...

local Join = { acks = {} }
ns.Join = Join

local CHANNEL = "ElternabendTreff"
local PASSWORD = "kinderschlafen"
local ANSWER_WAIT = 8 -- Sekunden auf Antworten warten

-- Wer Anfragen per Flüstern bekommt (Vorname Nachname, genau wie im Spiel).
-- Neue Offiziere hier ergänzen und eine neue Version veröffentlichen.
Join.INVITERS = {
    "Beta Lux",
}
Join.KEYWORD = "ginv"
-- Klartext im versteckten Kanal: kommt (anders als Addon-Nachrichten) auch von Nicht-Mitgliedern an
Join.CHANNEL_TEXT = "ginv"

-- „Kein Spieler namens '%s' ist online.“ → Suchmuster für die Spielsprache
local NOT_FOUND
if ERR_CHAT_PLAYER_NOT_FOUND_S then
    NOT_FOUND = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("%%%d%$", "%%"):gsub("([%(%)%.%-%+%[%]%*%?%^%$])", "%%%1"):gsub("%%s", "(.+)")
    NOT_FOUND = "^" .. NOT_FOUND .. "$"
end

-- Kanal -------------------------------------------------------------------------
function Join:ChannelId()
    local id = GetChannelName(CHANNEL)
    return id and id > 0 and id or nil
end

-- Hinweis: Den Kanal nicht mehr per ChatFrame_RemoveChannel aus den Chatfenstern nehmen.
-- Das verändert Blizzards Chatfenster und kann dazu führen, dass WoW Befehle wie
-- /ginvite dem Addon zurechnet und blockiert. Im Kanal laufen nur Addon-Nachrichten,
-- im Chat erscheint dort nichts; die Beitrittshinweise filtert FilterNotice unten.

function Join:EnsureChannel()
    if self:ChannelId() then return true end
    if self.joining and GetTime() - self.joining < 5 then return false end
    self.joining = GetTime()
    JoinTemporaryChannel(CHANNEL, PASSWORD)
    return false
end

function Join:LeaveChannel()
    if self:ChannelId() then LeaveChannelByName(CHANNEL) end
end

-- Kanalnummer: WoW vergibt beim Beitreten die kleinste freie Nummer. Tritt das Addon
-- früher bei als Allgemein/Handel, landet unser Kanal auf 1 und schiebt die anderen nach
-- hinten. Eine feste Nummer (etwa 40) lässt WoW nicht zu (höchstens 20 Kanäle), aber man
-- darf Kanäle tauschen: Wir schieben unseren Kanal Schritt für Schritt hinter alle anderen,
-- so behalten Allgemein, Handel usw. ihre gewohnte Reihenfolge.
local moveTries = 0
function Join:MoveChannelToEnd()
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    local id = self:ChannelId()
    if not swap or not id or moveTries >= 3 or InCombatLockdown() then return end
    local others = {}
    local list = { GetChannelList() } -- Nummer, Name, gesperrt, Nummer, Name, …
    for i = 1, #list, 3 do
        local n = tonumber(list[i])
        if n and n > id then others[#others + 1] = n end
    end
    if #others == 0 then return end -- schon ganz hinten
    table.sort(others)
    moveTries = moveTries + 1
    local pos = id
    for _, n in ipairs(others) do
        if not pcall(swap, pos, n) then return end
        pos = n
    end
end

local moveQueued
local function QueueMove()
    if moveQueued then return end
    moveQueued = true
    C_Timer.After(3, function()
        moveQueued = false
        Join:MoveChannelToEnd()
    end)
end
ns:On("CHANNEL_UI_UPDATE", QueueMove)
ns:On("CHAT_MSG_CHANNEL_NOTICE", QueueMove)

-- Hinweise wie „Kanal betreten: ElternabendTreff“ nicht im Chat anzeigen
local function FilterNotice(_, _, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and not ns.IsSecret(v) and v:find(CHANNEL, 1, true) then return true end
    end
end
local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then
    AddFilter("CHAT_MSG_CHANNEL_NOTICE", FilterNotice)
    AddFilter("CHAT_MSG_CHANNEL_NOTICE_USER", FilterNotice)
    AddFilter("CHAT_MSG_CHANNEL", FilterNotice)
    -- „X ist dem Channel beigetreten / hat den Channel verlassen“ (wenn die Beitrittsmeldungen eingeschaltet sind)
    AddFilter("CHAT_MSG_CHANNEL_JOIN", FilterNotice)
    AddFilter("CHAT_MSG_CHANNEL_LEAVE", FilterNotice)
end

-- Wer einladen darf, ist im Kanal; alle anderen in der Gilde nicht
function Join:CanReceive()
    return IsInGuild() and CanGuildInvite() and ns.db.recruit.enabled
end

-- Im Kanal sind: alle, die einladen dürfen – und wer gerade anfragt, nur für diese Zeit.
-- WoW lässt Addons nur im Moment eines Klicks in einen Kanal schreiben. Deshalb tritt der
-- Anfragende schon beim ersten Klick („Möchtest du beitreten?“) bei; beim zweiten Klick,
-- der die Anfrage abschickt, ist er dann drin.
local REQUEST_STAY = 120 -- Sekunden, die ein Anfragender nach dem Abschicken im Kanal bleibt

function Join:Asking()
    return not IsInGuild() and self.wantUntil ~= nil and GetTime() < self.wantUntil
end

function Join:UpdateMembership()
    if self:CanReceive() or self:Asking() then
        self:EnsureChannel()
    else
        self:LeaveChannel()
    end
end

-- Als Anfragender für eine Weile im Kanal bleiben, danach von selbst wieder gehen
function Join:StayFor(seconds)
    self.wantUntil = GetTime() + seconds
    self:EnsureChannel()
    C_Timer.After(seconds + 1, function() Join:UpdateMembership() end)
end

-- Anfragende Seite --------------------------------------------------------------
-- Das Addon gibt es öffentlich (CurseForge): Wer es nur ausprobiert, soll nicht aus
-- Versehen eine Anfrage an die ganze Gilde schicken. Erster Klick fragt nach, der zweite sendet.
local CONFIRM_SECONDS = 15

-- twink: beim zweiten Klick „Ich bin ein Twink“ (true) oder „Ich bin neu“ (false)
function Join:Click(twink)
    if self.confirmAt and GetTime() - self.confirmAt < CONFIRM_SECONDS then
        self.confirmAt = nil
        self:Request(twink)
        return
    end
    self.confirmAt = GetTime()
    self.state = "confirm"
    -- Schon jetzt in den Kanal: beim zweiten Klick muss man drin sein
    if not IsInGuild() then self:StayFor(CONFIRM_SECONDS + 5) end
    ns:Fire("JOIN_UPDATE")
    C_Timer.After(CONFIRM_SECONDS, function()
        if self.state == "confirm" and self.confirmAt and GetTime() - self.confirmAt >= CONFIRM_SECONDS - 0.1 then
            self.state, self.confirmAt = nil, nil
            ns:Fire("JOIN_UPDATE")
        end
    end)
end

-- Main für einen Twink: eigene Charaktere (accountweit), die schon in der Gilde sind.
-- Vorrang hat der als Main gewählte, sonst der mit der höchsten Stufe.
function Join:GuessMain()
    local me = ns.PlayerKey()
    local best
    for key, c in pairs(ns.db.myChars or {}) do
        if key ~= me and c.guild and ns.Info.GUILD_NAMES[c.guild] then
            if key == ns.db.myMain then return c.name end
            if not best or (c.level or 0) > (best.level or 0) then best = c end
        end
    end
    return best and best.name or nil
end

-- Was geflüstert und in den Kanal geschrieben wird
function Join:RequestText()
    local want = ns.db.joinAs and ns.db.joinAs[ns.PlayerKey()]
    if want and want.twink then
        return self.KEYWORD .. " twink" .. (want.main and (" " .. want.main) or "")
    end
    return self.KEYWORD
end

function Join:Request(twink)
    if IsInGuild() then
        ns.Print("Du bist schon in einer Gilde.")
        return
    end
    -- Merken (auch über einen Neustart hinweg): nach dem Beitritt meldet sich ein Twink selbst
    ns.db.joinAs = ns.db.joinAs or {}
    ns.db.joinAs[ns.PlayerKey()] = { twink = twink and true or false, main = twink and self:GuessMain() or nil, t = time() }
    wipe(self.acks)
    self.state = "sending"
    self:StayFor(REQUEST_STAY)
    ns:Fire("JOIN_UPDATE")

    -- Zuverlässiger Weg: „ginv“ an alle Einladenden flüstern
    self:WhisperInviters()
    -- Zusätzlich der alte Weg über den Kanal (klappt, wo Forever ihn zulässt)
    -- Klartext „ginv“ in den Kanal: Alle Mitglieder mit Addon sitzen darin und sehen die Anfrage.
    -- Muss direkt im Klick passieren (kein Timer, keine Warteschlange), sonst verwirft WoW es.
    self.posted = false
    local id = self:ChannelId()
    if id then
        local ok = pcall(C_ChatInfo.SendChatMessage, self:RequestText(), "CHANNEL", nil, id)
        self.posted = ok
        -- Alter Weg als Addon-Nachricht (für ältere Addon-Versionen)
        ns.Comm:Send("JOINREQ", ns.UnitFullName("player"), "CHANNEL", id)
    else
        -- Noch nicht im Kanal (der Beitritt braucht einen Moment): Geflüstert ist schon; der nächste Klick
        -- erreicht zusätzlich alle im Kanal
        ns.Print("Einen Moment – bitte in ein paar Sekunden nochmal auf „Der Gilde beitreten“ klicken.")
    end
    C_Timer.After(ANSWER_WAIT, function()
        if self.state == "sending" then
            if next(self.acks) or self:ReachedCount() > 0 then
                self.state = "sent"
            elseif self.posted then
                self.state = "posted"
            else
                self.state = "nobody"
            end
            ns:Fire("JOIN_UPDATE")
        end
    end)
end

-- Flüstern an alle aus INVITERS; wer offline ist, meldet das Spiel per Systemnachricht
function Join:WhisperInviters()
    self.whispered, self.offline = {}, {}
    local me = ns.PlayerKey()
    local text = self:RequestText()
    for _, name in ipairs(self.INVITERS) do
        local key = ns.NameKey(name)
        if key and key ~= me then
            self.whispered[key] = name
            ns.WhenChatFree(function() C_ChatInfo.SendChatMessage(text, "WHISPER", nil, name) end)
        end
    end
end

function Join:ReachedCount()
    local n = 0
    for key in pairs(self.whispered or {}) do
        if not self.offline[key] then n = n + 1 end
    end
    return n
end

-- Ein Name zum Selbst-Anflüstern, falls der Knopf nicht durchkommt
function Join:FallbackCommand()
    local name = self.INVITERS[1]
    return name and ("/w " .. name .. " " .. self.KEYWORD) or nil
end

-- „Kein Spieler namens … ist online“ für unsere Flüster-Anfragen: zählen und ausblenden
local function FilterNotFound(_, _, msg)
    if not NOT_FOUND or type(msg) ~= "string" or ns.IsSecret(msg) or not Join.whispered then return end
    local who = msg:match(NOT_FOUND)
    local key = who and ns.NameKey(who)
    if key and Join.whispered[key] then
        Join.offline[key] = true
        return true
    end
end
if AddFilter then AddFilter("CHAT_MSG_SYSTEM", FilterNotFound) end
-- Zählen auch dann, wenn kein Chatfenster Systemmeldungen zeigt
ns:On("CHAT_MSG_SYSTEM", function(msg) FilterNotFound(nil, nil, msg) end)

function Join:AckCount()
    local n = 0
    for _ in pairs(self.acks) do n = n + 1 end
    return n
end

-- Text für den Start-Reiter (kurz: höchstens zwei Zeilen neben dem Knopf)
function Join:StatusText()
    local n = math.max(self:AckCount(), self:ReachedCount())
    if self.state == "confirm" then
        local main = self:GuessMain()
        return "Bist du neu bei uns oder ein Twink" .. (main and (" (z. B. von " .. ns.ShortName(main) .. ")") or "") .. "?"
    elseif self.state == "sending" then
        return "Anfrage wird gesendet …"
    elseif self.state == "sent" then
        return (n == 1 and "Anfrage ist angekommen" or ("Anfrage ist bei " .. n .. " Einladenden angekommen"))
            .. " – gleich kommt die Einladung. Einfach annehmen!"
    elseif self.state == "posted" then
        return "Anfrage ist raus – wer aus der Gilde gerade online ist, sieht sie. Gleich kommt die Einladung."
    elseif self.state == "nobody" then
        return "Gerade ist niemand zum Einladen online. Später nochmal versuchen oder selbst flüstern:"
    end
end

ns.Comm.handlers.JOINACK = function(sender)
    Join.acks[ns.NameKey(sender) or sender] = true
    ns:Fire("JOIN_UPDATE")
end

-- Einladende Seite ---------------------------------------------------------------
ns.Comm.handlers.JOINREQ = function(sender)
    if not Join:CanReceive() then return end
    if ns.Recruit:Request(sender, "Addon") then
        ns.Comm:Send("JOINACK", nil, "WHISPER", sender)
    end
end

-- Klartext-Anfrage im versteckten Kanal (siehe Request)
ns:On("CHAT_MSG_CHANNEL", function(text, sender, _, channelName, _, _, _, _, channelBaseName)
    if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= "string" or not sender then return end
    local inChannel = channelBaseName == CHANNEL
        or (type(channelName) == "string" and not ns.IsSecret(channelName) and channelName:find(CHANNEL, 1, true))
    if not inChannel then return end
    local lower = ns.Lower(strtrim(text))
    local twink = lower:sub(1, #Join.CHANNEL_TEXT + 6) == Join.CHANNEL_TEXT .. " twink"
    if lower ~= Join.CHANNEL_TEXT and not twink then return end
    if ns.SameName(sender, ns.PlayerKey()) or not Join:CanReceive() then return end
    local main = twink and strtrim(strtrim(text):sub(#Join.CHANNEL_TEXT + 7)) or ""
    ns.Recruit:Request(sender, "Addon", twink, main ~= "" and main or nil)
end)

-- Ein anderer Einladender war schneller: Anfrage hier entfernen
ns.Comm.handlers.JOINDONE = function(sender, parts)
    if parts[2] then ns.Recruit:Drop(parts[2], ns.ShortName(sender)) end
end

-- Nach eigener Einladung den anderen Bescheid geben
function Join:Done(name)
    local id = self:ChannelId()
    if id then ns.Comm:Send("JOINDONE", name, "CHANNEL", id) end
end

-- Nach dem Beitritt: Als Twink selbst melden – Zuordnung zum Main für alle (wie „Das sind meine
-- Charaktere“) und eine kurze Zeile im Gildenchat. Neue Spieler: nichts, die Begrüßung kommt von der Gilde.
local JOIN_AS_TTL = 7 * 24 * 3600
function Join:AfterJoin()
    local me = ns.PlayerKey()
    local want = ns.db.joinAs and me and ns.db.joinAs[me]
    if not want then return end
    if not GetGuildInfo("player") then
        -- Gildenname ist direkt nach dem Beitritt manchmal noch nicht da: gleich nochmal
        self.retries = (self.retries or 0) + 1
        if self.retries <= 5 then C_Timer.After(3, function() Join:AfterJoin() end) end
        return
    end
    if not ns.Info:IsOurGuild() then return end
    ns.db.joinAs[me] = nil
    if not want.twink or time() - (want.t or 0) > JOIN_AS_TTL then return end
    local name = ns.UnitFullName("player")
    ns.Comm:Send("TWK", name .. "\t" .. (want.main or ""), "GUILD")
    if want.main then ns.Members:LinkMeAsTwink(want.main) end
    ns.SendChat(want.main and ("Hallo zusammen, ich bin ein neuer Twink von " .. ns.ShortName(want.main) .. ".")
        or "Hallo zusammen, ich bin ein neuer Twink.", "GUILD")
end

-- Events -----------------------------------------------------------------------
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(10, function()
        Join:UpdateMembership()
        if IsInGuild() then Join:AfterJoin() end -- Einladung angenommen, aber gleich ausgeloggt
    end)
end)
ns:On("PLAYER_GUILD_UPDATE", function()
    C_Timer.After(2, function()
        if IsInGuild() and Join.state then
            Join.state = nil -- Beitritt geklappt
            ns:Fire("JOIN_UPDATE")
        end
        if IsInGuild() then Join:AfterJoin() end
        Join:UpdateMembership()
    end)
end)
ns:Listen("RECRUIT_UPDATE", function() Join:UpdateMembership() end)
