-- Elternabend Raid: Gildeneinladung per Flüstern („ginv“)
--
-- Gildeneinladungen sind in WoW Forever der Blizzard-Oberfläche vorbehalten. Weder das
-- Addon noch ein Makro darf einladen, und das Addon darf auch die Eingabezeile nicht
-- anfassen (weder öffnen noch Text einsetzen) – sonst rechnet WoW selbst einen von Hand
-- abgeschickten /ginvite dem Addon zu und blockiert ihn. Getestet am 05.11.2026.
-- Das Addon zeigt deshalb nur den fertigen Befehl markiert zum Kopieren an (eigenes Textfeld). Ob die Einladung
-- rausging, zeigt die Systemmeldung „Ihr habt … eingeladen“; dann räumt das Addon auf.
local _, ns = ...

local Recruit = { queue = {}, recent = {} }
ns.Recruit = Recruit

BINDING_HEADER_ELTERNABEND = "Elternabend"
BINDING_NAME_ELTERNABEND_GILDENEINLADUNG = "Nächste Gildenanfrage einladen"

local REPEAT_SECONDS = 30 -- doppelte Anfragen derselben Person ignorieren
local LOG_SIZE = 100

local function Settings()
    return ns.db.recruit
end

local function Whisper(name, text)
    if not text or text == "" then return end
    ns.WhenChatFree(function() C_ChatInfo.SendChatMessage(text, "WHISPER", nil, name) end)
end

-- Systemmeldung der Spielsprache ("%s ist der Gilde beigetreten.") → Suchmuster
local function Pattern(fmt)
    if not fmt then return nil end
    fmt = fmt:gsub("%%%d%$", "%%")
    fmt = fmt:gsub("([%(%)%.%-%+%[%]%*%?%^%$])", "%%%1")
    fmt = fmt:gsub("%%s", "(.+)")
    return "^" .. fmt .. "$"
end

local JOINED = Pattern(ERR_GUILD_JOIN_S)
local INVITED = Pattern(ERR_GUILD_INVITE_S) -- „Ihr habt %s eingeladen …“ – auch bei Einladungen über das Gildenfenster
local DECLINED = Pattern(ERR_GUILD_DECLINE_S)
local ALREADY = Pattern(ERR_ALREADY_IN_GUILD_S)

-- Erkennen -------------------------------------------------------------------
function Recruit:Keywords()
    local list = {}
    for word in (Settings().keywords or ""):gmatch("[^,]+") do
        word = ns.Lower(strtrim(word))
        if word ~= "" then list[word] = true end
    end
    return list
end

-- Zählt, wenn das erste Wort der Nachricht ein Stichwort ist („ginv“, „ginv bitte“, „Ginv!“)
function Recruit:Matches(msg)
    local first = ns.Lower(strtrim(msg)):match("^(%S+)")
    if not first then return false end
    first = first:gsub("[%p]+$", "")
    return self:Keywords()[first] == true
end

-- Verlauf ----------------------------------------------------------------------
function Recruit:Log(name, status)
    local log = Settings().log
    local key = ns.NameKey(name)
    for _, e in ipairs(log) do
        if ns.SameName(e.key, key) and time() - e.time < 3600 then
            e.status, e.time = status, time()
            ns:Fire("RECRUIT_UPDATE")
            return
        end
    end
    table.insert(log, 1, { name = ns.ShortName(name), full = name, key = key, time = time(), status = status })
    while #log > LOG_SIZE do table.remove(log) end
    ns:Fire("RECRUIT_UPDATE")
end

function Recruit:LastStatus(key)
    for _, e in ipairs(Settings().log) do
        if ns.SameName(e.key, key) then return e.status end
    end
end

-- Warteschlange --------------------------------------------------------------
local function Remove(key)
    for i = #Recruit.queue, 1, -1 do
        if ns.SameName(Recruit.queue[i].key, key) then table.remove(Recruit.queue, i) end
    end
end

-- Stumm: Neue Anfragen melden sich nicht mit Fenster und Ton, sondern sammeln sich still im Reiter „Invite“
-- (mit Plakette am Reiter). Entweder von Hand ausgeschaltet oder automatisch in Dungeons und Raids.
-- Liefert true und den Grund ("aus" oder "instanz").
function Recruit:Quiet()
    local s = Settings()
    if s.popup == false then return true, "aus" end
    if s.quietInstance ~= false then
        local inInstance, kind = IsInInstance()
        if inInstance and (kind == "party" or kind == "raid" or kind == "scenario") then return true, "instanz" end
    end
    return false
end

-- Fenster und Ton für neue Anfragen ein- oder ausschalten
function Recruit:SetPopup(on)
    Settings().popup = on and true or false
    local waiting = #self.queue
    if on then
        local quiet = self:Quiet()
        ns.Print("Gildenanfragen: Fenster und Ton sind " .. ns.Theme.Hex("green", "an") .. "."
            .. (quiet and " Hier im Dungeon oder Raid bleibt es trotzdem still (Einstellung im Reiter Invite)." or "")
            .. (waiting > 0 and (" " .. (waiting == 1 and "1 Anfrage wartet." or (waiting .. " Anfragen warten."))) or ""))
    else
        ns.Print("Gildenanfragen sind stumm: kein Fenster, kein Ton. Neue Anfragen sammeln sich im Reiter Invite. "
            .. "Wieder einschalten: dort oder mit |cfff3dc9a/ea anfragen|r.")
    end
    ns:Fire("RECRUIT_UPDATE")
end

-- source: nil = per Flüstern, "Addon" = Knopf „Der Gilde beitreten“.
-- Liefert true, wenn die Anfrage in der Warteschlange steht.
function Recruit:Request(sender, source)
    local key = ns.NameKey(sender)
    if not key then return end
    for _, q in ipairs(self.queue) do
        if ns.SameName(q.key, key) then return true end
    end
    local now = GetTime()
    if self.recent[key] and now - self.recent[key] < REPEAT_SECONDS then return end
    self.recent[key] = now

    if not IsInGuild() or not CanGuildInvite() then
        ns.Print(ns.ShortName(sender) .. " möchte in die Gilde – du darfst gerade aber niemanden einladen.")
        return
    end
    if C_GuildInfo.MemberExistsByName and C_GuildInfo.MemberExistsByName(sender) then
        Whisper(sender, "Du bist schon in der Gilde Elternabend. :)")
        return
    end
    table.insert(self.queue, { name = sender, key = key, time = time(), source = source })
    self:Log(sender, source and ("angefragt (" .. source .. ")") or "angefragt")
    if not self:Quiet() then PlaySound(SOUNDKIT.READY_CHECK) end
    return true
end

-- Ein anderer Einladender hat die Person schon eingeladen
function Recruit:Drop(name, by)
    Remove(ns.NameKey(name))
    self:Log(name, by and ("von " .. by .. " eingeladen") or "erledigt")
end

-- Einladung ist raus (Systemmeldung „Ihr habt … eingeladen“): aufräumen und Bescheid geben.
-- Geflüstert wird an den Namen genau so, wie das Spiel ihn bei der Anfrage geliefert hat –
-- in WoW Forever mit Vor- und Nachnamen.
function Recruit:Invited(name)
    local key = ns.NameKey(name)
    local target
    for _, q in ipairs(self.queue) do
        if ns.SameName(q.key, key) then target = q.name break end
    end
    if not target then return false end
    Remove(key)
    self:Log(target, "eingeladen")
    Whisper(target, Settings().reply)
    if ns.Join then ns.Join:Done(target) end
    return true
end

-- Befehl, den man zum Einladen selbst tippen muss
function Recruit:Command(name)
    return name and ("/ginvite " .. name) or nil
end

-- „Einladen“: Befehl im Anfrage-Fenster markiert zum Kopieren zeigen (Eingabezeile bleibt unberührt)
function Recruit:Invite(name)
    if not name then return end
    ns:Fire("RECRUIT_COPY", name)
end

function Recruit:InviteNext()
    local q = self.queue[1]
    if q then
        self:Invite(q.name)
    else
        ns.Print("Keine offenen Gildenanfragen.")
    end
end

function Recruit:NextName()
    return self.queue[1] and self.queue[1].name
end

-- Macht aus einem Knopf einen „Einladen“-Knopf. getName(knopf) liefert den Namen (oder nil).
function Recruit:SetupInviteButton(btn, getName)
    btn:SetScript("OnClick", function(self) Recruit:Invite(getName(self)) end)
end

-- Version 4.2.2 hatte die Taste auf einen Makro-Knopf umgestellt, den Forever ebenfalls
-- blockiert. Hier wieder zurück auf die normale Belegung.
local function MigrateBinding()
    if InCombatLockdown() then return end
    local changed = false
    for _, key in ipairs({ GetBindingKey("CLICK ElternabendNaechsteEinladung:LeftButton") }) do
        if key then
            SetBinding(key, "ELTERNABEND_GILDENEINLADUNG")
            changed = true
        end
    end
    if changed then SaveBindings(GetCurrentBindingSet()) end
end
ns:On("PLAYER_LOGIN", function() C_Timer.After(5, MigrateBinding) end)

function Recruit:Decline(name)
    Remove(ns.NameKey(name))
    self:Log(name, "verworfen")
end

-- Namen aus Systemmeldungen säubern (Farbcodes und anklickbare Spielernamen entfernen)
local function CleanName(name)
    if not name then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("|H.-|h%[?(.-)%]?|h", "%1")
    name = name:gsub("^%[(.-)%]$", "%1")
    return strtrim(name)
end

-- Events -----------------------------------------------------------------------
ns:On("CHAT_MSG_WHISPER", function(msg, sender)
    if not ns.db or not Settings().enabled then return end
    if ns.IsSecret(msg) or ns.IsSecret(sender) then return end
    if Recruit:Matches(msg) then Recruit:Request(sender) end
end)

ns:On("CHAT_MSG_SYSTEM", function(msg)
    if not ns.db or ns.IsSecret(msg) then return end
    -- Eigene Einladung, egal ob per Addon, Gildenfenster oder /ginvite: merken für die Antwort per Flüstern
    local invited = CleanName(INVITED and msg:match(INVITED))
    if invited then
        if not Recruit:Invited(invited) then Recruit:Log(invited, "eingeladen") end
        return
    end

    local name = CleanName(JOINED and msg:match(JOINED))
    if name then
        local key = ns.NameKey(name)
        -- Beigetreten (egal wer eingeladen hat): offene Anfrage wegräumen, Verlauf aktualisieren
        Remove(key)
        if Recruit:LastStatus(key) then Recruit:Log(name, "beigetreten") end
        ns:Fire("RECRUIT_UPDATE")
        -- Keine automatische Begrüßung im Gildenchat mehr: Mit vielen Addons in der Gilde
        -- kam sie zu oft. Begrüßt wird von Hand.
        return
    end
    name = CleanName(DECLINED and msg:match(DECLINED))
    if name then
        Recruit:Log(name, "abgelehnt")
        return
    end
    name = CleanName(ALREADY and msg:match(ALREADY))
    if name then Recruit:Log(name, "schon in einer Gilde") end
end)

-- Aus dem Dungeon oder Raid zurück: Anfragen, die sich still gesammelt haben, jetzt zeigen
local function AfterZoneChange()
    C_Timer.After(3, function()
        if not ns.db or #Recruit.queue == 0 then return end
        local quiet = Recruit:Quiet()
        if Recruit.wasQuiet and not quiet then
            local n = #Recruit.queue
            ns.Print(n == 1 and "Eine Gildenanfrage hat gewartet, solange du im Dungeon oder Raid warst."
                or (n .. " Gildenanfragen haben gewartet, solange du im Dungeon oder Raid warst."))
            PlaySound(SOUNDKIT.READY_CHECK)
        end
        Recruit.wasQuiet = quiet
        ns:Fire("RECRUIT_UPDATE")
    end)
end
ns:On("PLAYER_ENTERING_WORLD", function()
    Recruit.wasQuiet = ns.db and Recruit:Quiet() or false
    AfterZoneChange()
end)
ns:On("ZONE_CHANGED_NEW_AREA", AfterZoneChange)
ns:Listen("RECRUIT_UPDATE", function() Recruit.wasQuiet = Recruit:Quiet() end)
