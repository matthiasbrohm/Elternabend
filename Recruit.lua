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
-- Begrüßung erst nach einer kurzen Pause: Direkt nach dem Beitritt ist der Gildenchat
-- beim neuen Mitglied noch nicht verbunden, und es würde den Gruß verpassen.
local WELCOME_DELAY = 10
local WELCOME_TRIES = 3
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
    PlaySound(SOUNDKIT.READY_CHECK)
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

-- Steht der Name schon in der Gildenliste? (Vergleich mit und ohne Realm, Vor-/Nachname)
local function InGuildRoster(name)
    for i = 1, GetNumGuildMembers() do
        local n = GetGuildRosterInfo(i)
        if n and not ns.IsSecret(n) and ns.SameName(n, name) then return true end
    end
    return false
end

-- Begrüßung im Gildenchat: warten, Gildenliste auffrischen und schreiben, sobald das neue
-- Mitglied darin steht. Spätestens nach dem letzten Versuch wird trotzdem gegrüßt – der
-- Beitritt ist ja gemeldet.
-- Begrüßung: Seit alle einladen dürfen, begrüßt nicht mehr nur, wer eingeladen hat, sondern
-- das erste Addon in der Gilde, das den Beitritt sieht. Damit nicht alle gleichzeitig grüßen,
-- wartet jedes Addon zufällig ein paar Sekunden und schweigt, wenn schon jemand den Neuen
-- im Gildenchat mit „Willkommen“ und seinem Namen begrüßt hat.
Recruit.pendingWelcome = {}

local function FirstName(name)
    local short = ns.ShortName(name) or name or ""
    return short:match("^(%S+)") or short
end

function Recruit:WelcomeText(name)
    local fmt = Settings().welcomeText
    if not fmt or fmt == "" or not fmt:find("%%s") then
        fmt = "Willkommen bei Elternabend, %s! Die Kinder schlafen, die Helden erwachen. Stell dich bitte kurz in unserem Discord vor (gilde-elternabend.de/discord), dann stufen wir dich vom Initial zum Mitglied hoch."
    end
    return string.format(fmt, ns.ShortName(name) or name)
end

function Recruit:Welcome(name, try)
    local key = ns.NameKey(name)
    if not key then return end
    if try == 1 then
        self.pendingWelcome[key] = ns.Lower(FirstName(name))
    end
    C_GuildInfo.GuildRoster()
    local wait = try == 1 and (WELCOME_DELAY + math.random() * 10) or WELCOME_DELAY
    C_Timer.After(wait, function()
        if not Recruit.pendingWelcome[key] then return end -- jemand anderes war schneller
        if not InGuildRoster(name) and try < WELCOME_TRIES then
            Recruit:Welcome(name, try + 1)
            return
        end
        ns.WhenChatFree(function()
            if not Recruit.pendingWelcome[key] then return end
            Recruit.pendingWelcome[key] = nil
            C_ChatInfo.SendChatMessage(Recruit:WelcomeText(name), "GUILD")
        end)
    end)
end

-- Begrüßt schon jemand anderes? (Addon oder von Hand: „Willkommen“ + Vorname)
ns:On("CHAT_MSG_GUILD", function(text, sender)
    if not next(Recruit.pendingWelcome) then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= "string" then return end
    if ns.SameName(sender, ns.PlayerKey()) then return end
    local lower = ns.Lower(text)
    if not lower:find("willkommen", 1, true) then return end
    for key, first in pairs(Recruit.pendingWelcome) do
        if first ~= "" and lower:find(first, 1, true) then Recruit.pendingWelcome[key] = nil end
    end
end)

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
    -- Eigene Einladung, egal ob per Addon, Gildenfenster oder /ginvite: merken für die Begrüßung
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
        -- Jedes Addon in der Gilde kann begrüßen – aber nur eins tut es (siehe Welcome)
        if Settings().welcome and not ns.SameName(name, ns.PlayerKey()) then Recruit:Welcome(name, 1) end
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
