-- Elternabend: „Der Gilde beitreten“ per Knopf
--
-- Wer noch nicht in der Gilde ist, erreicht den Gildenkanal des Addons nicht. Deshalb
-- treten Einladende (alle, die einladen dürfen) und Anfragende im Hintergrund einem
-- versteckten Chat-Kanal bei; darüber gehen nur Addon-Nachrichten, im Chat sieht man
-- ihn nicht. Die Anfrage landet bei den Einladenden im bekannten Gildenanfrage-Fenster;
-- eingeladen wird weiterhin per Klick (WoW erlaubt es nicht ohne).
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

function Join:UpdateMembership()
    if self:CanReceive() then
        self:EnsureChannel()
    elseif IsInGuild() then
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

    local function Send()
        local id = self:ChannelId()
        if not id then
            self.state = "failed"
            ns:Fire("JOIN_UPDATE")
            return
        end
        ns.Comm:Send("JOINREQ", ns.UnitFullName("player"), "CHANNEL", id)
        C_Timer.After(ANSWER_WAIT, function()
            if self.state == "sending" then
                self.state = next(self.acks) and "sent" or "nobody"
                ns:Fire("JOIN_UPDATE")
            end
        end)
    end
    -- Beitritt zum Kanal dauert einen Moment
    if self:EnsureChannel() then Send() else C_Timer.After(2, Send) end
end

function Join:AckCount()
    local n = 0
    for _ in pairs(self.acks) do n = n + 1 end
    return n
end

-- Text für den Start-Reiter (kurz: höchstens zwei Zeilen neben dem Knopf)
function Join:StatusText()
    local n = self:AckCount()
    if self.state == "sending" then
        return n > 0 and ("Angekommen bei " .. n .. " Einladenden …") or "Anfrage wird gesendet …"
    elseif self.state == "sent" then
        return "Angekommen bei " .. n .. " Einladenden – gleich kommt die Einladung."
    elseif self.state == "nobody" then
        return "Gerade ist niemand zum Einladen online."
    elseif self.state == "failed" then
        return "Hat nicht geklappt – bitte nochmal klicken."
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
