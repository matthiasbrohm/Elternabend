-- Elternabend: „Der Gilde beitreten“ per Knopf
--
-- Wer noch nicht in der Gilde ist, erreicht den Gildenkanal des Addons nicht. Deshalb
-- treten Einladende (alle, die einladen dürfen) und Anfragende im Hintergrund einem
-- versteckten Chat-Kanal bei; darüber gehen nur Addon-Nachrichten, im Chat sieht man
-- ihn nicht. Die Anfrage landet bei den Einladenden im bekannten Gildenanfrage-Fenster;
-- eingeladen wird weiterhin per Klick (WoW erlaubt es nicht ohne).
--
-- In WoW Forever kommen Addon-Nachrichten über den Kanal von Nicht-Mitgliedern nicht an
-- (getestet am 05.11.2026). Deshalb flüstert der Knopf zusätzlich ganz normal „ginv“ an
-- alle aus INVITERS – das landet bei ihnen in der Gildenanfrage wie ein getipptes „ginv“.
-- Wer gerade offline ist, bekommt nichts; die Meldung „Kein Spieler namens …“ wird
-- ausgeblendet und gezählt.
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
end

-- Wer einladen darf, ist im Kanal; alle anderen in der Gilde nicht
function Join:CanReceive()
    return IsInGuild() and CanGuildInvite() and ns.db.recruit.enabled
end

-- Im Kanal sind: alle, die einladen dürfen – und alle, die noch nicht in der Gilde sind.
-- Letztere schon vor dem Klick: WoW lässt Addons nur im Moment eines Klicks in einen
-- Kanal schreiben. Müsste man erst beitreten, wäre der Klick vorbei und die Anfrage weg.
function Join:UpdateMembership()
    if self:CanReceive() or not IsInGuild() then
        self:EnsureChannel()
    else
        self:LeaveChannel()
    end
end

-- Anfragende Seite --------------------------------------------------------------
function Join:Request()
    if IsInGuild() then
        ns.Print("Du bist schon in einer Gilde.")
        return
    end
    wipe(self.acks)
    self.state = "sending"
    ns:Fire("JOIN_UPDATE")

    -- Zuverlässiger Weg: „ginv“ an alle Einladenden flüstern
    self:WhisperInviters()
    -- Zusätzlich der alte Weg über den Kanal (klappt, wo Forever ihn zulässt)
    -- Klartext „ginv“ in den Kanal: Alle Mitglieder mit Addon sitzen darin und sehen die Anfrage.
    -- Muss direkt im Klick passieren (kein Timer, keine Warteschlange), sonst verwirft WoW es.
    self.posted = false
    local id = self:ChannelId()
    if id then
        local ok = pcall(C_ChatInfo.SendChatMessage, Join.CHANNEL_TEXT, "CHANNEL", nil, id)
        self.posted = ok
        -- Alter Weg als Addon-Nachricht (für ältere Addon-Versionen)
        ns.Comm:Send("JOINREQ", ns.UnitFullName("player"), "CHANNEL", id)
    else
        -- Noch nicht im Kanal (z. B. direkt nach dem Einloggen): jetzt beitreten, nächster Klick klappt
        self:EnsureChannel()
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
    for _, name in ipairs(self.INVITERS) do
        local key = ns.NameKey(name)
        if key and key ~= me then
            self.whispered[key] = name
            ns.WhenChatFree(function() C_ChatInfo.SendChatMessage(self.KEYWORD, "WHISPER", nil, name) end)
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
    if self.state == "sending" then
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
    if not inChannel or ns.Lower(strtrim(text)) ~= Join.CHANNEL_TEXT then return end
    if ns.SameName(sender, ns.PlayerKey()) or not Join:CanReceive() then return end
    ns.Recruit:Request(sender, "Addon")
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

-- Events -----------------------------------------------------------------------
ns:On("PLAYER_LOGIN", function() C_Timer.After(10, function() Join:UpdateMembership() end) end)
ns:On("PLAYER_GUILD_UPDATE", function()
    C_Timer.After(2, function()
        if IsInGuild() and Join.state then
            Join.state = nil -- Beitritt geklappt
            ns:Fire("JOIN_UPDATE")
        end
        Join:UpdateMembership()
    end)
end)
ns:Listen("RECRUIT_UPDATE", function() Join:UpdateMembership() end)
