-- Elternabend Raid: Gildeneinladung per Flüstern („ginv“)
--
-- Gildeneinladungen sind im Client der Blizzard-Oberfläche vorbehalten: Ruft ein
-- Addon C_GuildInfo.Invite selbst auf, blockiert WoW das („Funktion, die Blizzard
-- vorbehalten ist“). Erlaubt ist aber ein Klick auf einen geschützten Knopf, der
-- den Chatbefehl „/ginvite Name“ ausführt – genau wie ein Makro. Deshalb liegt über
-- jedem „Einladen“-Knopf unsichtbar so ein geschützter Knopf (siehe unten), und die
-- eigene Taste aus den Tastenbelegungen klickt einen solchen Knopf.
-- Im Kampf lassen sich geschützte Knöpfe nicht umstellen; Einladen geht dann erst danach.
local _, ns = ...

local Recruit = { queue = {}, recent = {} }
ns.Recruit = Recruit

BINDING_HEADER_ELTERNABEND = "Elternabend"
BINDING_NAME_ELTERNABEND_GILDENEINLADUNG = "Nächste Gildenanfrage einladen (alt)"
_G["BINDING_NAME_CLICK ElternabendNaechsteEinladung:LeftButton"] = "Nächste Gildenanfrage einladen"

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

-- Nach dem Klick auf einen geschützten Einladen-Knopf: aufräumen und Bescheid geben.
-- „name“ ist der Absender genau so, wie das Spiel ihn liefert – in WoW Forever
-- mit Vor- und Nachnamen, sonst kommt die Einladung nicht an.
function Recruit:Invited(name)
    Remove(ns.NameKey(name))
    self:Log(name, "eingeladen")
    Whisper(name, Settings().reply)
    if ns.Join then ns.Join:Done(name) end
end

-- Wird nur noch erreicht, wenn der geschützte Knopf nicht greifen konnte (z. B. im Kampf)
function Recruit:Invite()
    if InCombatLockdown() then
        ns.Print("Gildeneinladungen gehen erst nach dem Kampf.")
    else
        ns.Print("Bitte nochmal auf „Einladen“ klicken.")
    end
end

function Recruit:InviteNext()
    if not self.queue[1] then
        ns.Print("Keine offenen Gildenanfragen.")
    else
        self:Invite()
    end
end

function Recruit:NextName()
    return self.queue[1] and self.queue[1].name
end

-- Geschützte Knöpfe ----------------------------------------------------------------
-- Tastendruck und Mausklick lösen den Knopf beim Drücken oder Loslassen aus – je nach
-- Einstellung „ActionButtonUseKeyDown“. Nur in dieser Phase zählt der Klick.
local function Acts(down)
    return (down and true or false) == (GetCVarBool("ActionButtonUseKeyDown") and true or false)
end

local function MakeSecure(name, parent)
    local b = CreateFrame("Button", name, parent or UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    return b
end

local function Arm(b, target)
    if InCombatLockdown() then return false end
    b.inviteName = target
    b:SetAttribute("macrotext", target and ("/ginvite " .. target) or "")
    return target ~= nil
end

local function AfterClick(b, down)
    if not Acts(down) then return end
    local target = b.inviteName
    if not InCombatLockdown() then Arm(b, nil) end
    if target then Recruit:Invited(target) end
end

-- Für die eigene Taste: „CLICK ElternabendNaechsteEinladung:LeftButton“ (Bindings.xml)
local nextButton = MakeSecure("ElternabendNaechsteEinladung")
nextButton:SetSize(1, 1)
nextButton:SetAlpha(0)
nextButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
nextButton:SetScript("PreClick", function(self, _, down)
    if not Acts(down) then return end
    if InCombatLockdown() then
        ns.Print("Gildeneinladungen gehen erst nach dem Kampf.")
    elseif not Arm(self, Recruit:NextName()) then
        ns.Print("Keine offenen Gildenanfragen.")
    end
end)
nextButton:SetScript("PostClick", function(self, _, down) AfterClick(self, down) end)

-- Für die sichtbaren „Einladen“-Knöpfe: ein unsichtbarer geschützter Knopf legt sich
-- beim Draufzeigen genau darüber. Verankert wird er an UIParent, nicht am Fenster –
-- so bleibt das Addon-Fenster frei beweglich und lässt sich auch im Kampf schließen.
local overlay = MakeSecure("ElternabendEinladenKnopf")
overlay:SetFrameStrata("TOOLTIP")
overlay:Hide()

local function HideOverlay()
    if overlay.owner then overlay.owner:UnlockHighlight() end
    overlay.owner = nil
    if not InCombatLockdown() then
        Arm(overlay, nil)
        overlay:Hide()
    end
end

overlay:SetScript("PreClick", function(self, _, down)
    if not Acts(down) then return end
    local owner = self.owner
    -- Kurz vor dem Klick nochmal den aktuellen Namen setzen (die Liste kann sich geändert haben)
    if owner and owner.inviteName then Arm(self, owner.inviteName(owner)) end
end)
overlay:SetScript("PostClick", function(self, _, down)
    if not Acts(down) then return end
    AfterClick(self, down)
    C_Timer.After(0, HideOverlay)
end)
overlay:SetScript("OnLeave", HideOverlay)
overlay:SetScript("OnHide", function(self)
    if self.owner then self.owner:UnlockHighlight() end
    self.owner = nil
end)

local function ShowOverlay(owner)
    if InCombatLockdown() or not owner:IsVisible() or not owner:IsEnabled() then return end
    local target = owner.inviteName(owner)
    if not target then return end
    local left, bottom, width, height = owner:GetLeft(), owner:GetBottom(), owner:GetWidth(), owner:GetHeight()
    if not left or not bottom then return end
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    overlay:SetSize(width * scale, height * scale)
    Arm(overlay, target)
    overlay.owner = owner
    overlay:Show()
    owner:LockHighlight()
end

-- Macht aus einem normalen Knopf einen „Einladen“-Knopf.
-- getName(knopf) liefert den Namen, der eingeladen werden soll (oder nil).
function Recruit:SetupInviteButton(btn, getName)
    btn.inviteName = getName
    btn:HookScript("OnEnter", ShowOverlay)
    btn:SetScript("OnClick", function() Recruit:Invite() end)
end

-- Kampf beginnt: Overlay ist dann gesperrt – vorher wegräumen
ns:On("PLAYER_REGEN_DISABLED", function()
    if overlay:IsShown() then HideOverlay() end
end)

-- Alte Taste (Lua-Aufruf, wird inzwischen blockiert) auf den geschützten Knopf umstellen
local function MigrateBinding()
    if InCombatLockdown() then return end
    local changed = false
    for _, key in ipairs({ GetBindingKey("ELTERNABEND_GILDENEINLADUNG") }) do
        if key then
            SetBinding(key, "CLICK ElternabendNaechsteEinladung:LeftButton")
            changed = true
        end
    end
    if changed then
        SaveBindings(GetCurrentBindingSet())
        ns.Print("Deine Taste für „Nächste Gildenanfrage einladen“ wurde auf die neue Einladung umgestellt.")
    end
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
function Recruit:Welcome(name, try)
    C_GuildInfo.GuildRoster()
    C_Timer.After(WELCOME_DELAY, function()
        if not InGuildRoster(name) and try < WELCOME_TRIES then
            Recruit:Welcome(name, try + 1)
            return
        end
        local text = string.format("Willkommen bei Elternabend, %s! Schön, dass du da bist.", ns.ShortName(name))
        ns.WhenChatFree(function() C_ChatInfo.SendChatMessage(text, "GUILD") end)
    end)
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
    local invited = INVITED and msg:match(INVITED)
    if invited then
        Recruit:Log(invited, "eingeladen")
        return
    end

    local name = JOINED and msg:match(JOINED)
    if name then
        local key = ns.NameKey(name)
        if Recruit:LastStatus(key) == "eingeladen" then
            Recruit:Log(name, "beigetreten")
            if Settings().welcome then Recruit:Welcome(name, 1) end
        end
        return
    end
    name = DECLINED and msg:match(DECLINED)
    if name then
        Recruit:Log(name, "abgelehnt")
        return
    end
    name = ALREADY and msg:match(ALREADY)
    if name then Recruit:Log(name, "schon in einer Gilde") end
end)
