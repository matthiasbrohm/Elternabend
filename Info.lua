-- Elternabend: Infos zur Gilde und Begrüßung
--
-- Die festen Infos stehen hier und kommen mit jeder Addon-Version. Die Nachricht
-- des Tages kommt live aus dem Spiel (die Gildenleitung ändert sie wie gewohnt
-- im Gildenfenster).
local ADDON, ns = ...

local Info = {}
ns.Info = Info

Info.GUILD = {
    name = "Elternabend",
    tagline = "Die familienfreundliche Gilde – Raids ab 21 Uhr, wenn die Kinder schlafen.",
    motto = "„Die Kinder schlafen. Die Helden erwachen.“",
    about = "Wir sind eine entspannte Gilde, gegründet von Eltern für Eltern. Allianz, ganz auf PvE: " ..
        "Dungeons, Raids und gemeinsames Vorankommen. Bei uns zählen Spaß, Zusammenhalt und ein " ..
        "freundlicher Umgangston – und ruft ein Kind, ist AFK völlig in Ordnung.",
    raidTimes = "Raids starten ab 21 Uhr – wenn im Kinderzimmer Ruhe ist.",
    raidHint = "Termine, Anmeldung und Soft-Reserves: Raidplaner auf der Webseite oder im Discord.",
    discord = "https://discord.gg/elternabend",
    website = "https://www.gilde-elternabend.de",
}

-- Gildennamen, bei denen die Begrüßung erscheint: WoW Forever und die Testgilde in Retail
Info.GUILD_NAMES = { ["Elternabend"] = true, ["Der Elternabend"] = true }

function Info:IsOurGuild()
    local guild = IsInGuild() and GetGuildInfo("player")
    return guild ~= nil and self.GUILD_NAMES[guild] == true
end

-- Heimatgilde: die Gilde, deren Daten (Berufe, Raid, Pinnwand, Raidtermine) das Addon auf diesem Account
-- gesammelt hat. Die Daten liegen accountweit auf dem Rechner – ein Charakter ohne Gilde oder in einer
-- anderen Gilde soll sie trotzdem nicht sehen und auch nicht weitergeben.
-- ns.db.homeGuild merkt sich die Gilde, ns.db.homeSeen, wann zuletzt ein Charakter dort eingeloggt war.
local HOME_MOVE_AFTER = 60 * 86400 -- so lange kein Charakter mehr in der alten Gilde war, darf eine neue übernehmen

-- Gildenwechsel: was der alten Gilde gehörte, geht nicht mit
local function ForgetGuildData()
    local db = ns.db
    db.board.notes, db.board.seen = {}, {}
    for key, char in pairs(db.professions) do
        if not char.mine then db.professions[key] = nil end
    end
    db.calendar.raids = { version = 0, list = {} }
    db.softres = { items = {} }
    db.orders = { out = {}, inc = {}, outbox = {} }
    db.links, db.profiles, db.fame, db.history = {}, {}, {}, {}
    db.plan, db.nextRaid, db.session = nil, nil, nil
end

function Info:AtHome()
    if not IsInGuild() then return false end
    local guild = GetGuildInfo("player")
    if not guild then return false end -- kurz nach dem Einloggen ist der Gildenname noch nicht da
    local db = ns.db
    if db.homeGuild == guild then
        db.homeSeen = time()
        return true
    end
    local function Adopt()
        if db.homeGuild then ForgetGuildData() end
        db.homeGuild, db.homeSeen = guild, time()
        return true
    end
    -- Die eigene Gilde des Addons geht immer vor
    if self:IsOurGuild() then return Adopt() end
    if db.homeGuild then
        -- War lange kein Charakter mehr in der alten Gilde, gehört das Addon jetzt hierher (ohne die alten Daten)
        if time() - (db.homeSeen or 0) > HOME_MOVE_AFTER then return Adopt() end
        return false
    end
    -- Andere Gilde und noch nichts gemerkt: Gehören die gespeicherten Berufe zu dieser Gilde?
    local M = ns.Members
    if not M or #M.list == 0 then return false end -- Gildenliste noch nicht geladen
    local total, here = 0, 0
    for key in pairs(db.professions or {}) do
        total = total + 1
        if M.byKey[key] then here = here + 1 end
    end
    if total == 0 or here * 2 > total then return Adopt() end
    return false
end

-- Nachricht des Tages: kommt mit dem Event GUILD_MOTD (beim Einloggen und bei jeder Änderung).
-- GetGuildRosterMOTD() selbst rufen wir nicht mehr auf – in WoW Forever wird der Aufruf
-- aus Addons teils blockiert (ADDON_ACTION_BLOCKED). Gemerkt wird sie pro Gilde.
local function GuildKey()
    local guild = IsInGuild() and GetGuildInfo("player")
    if not guild or ns.IsSecret(guild) then return nil end
    return guild
end

function Info:SetMOTD(text)
    if text == nil or ns.IsSecret(text) then return end
    self.current = text -- beim Einloggen kennt der Client den Gildennamen manchmal noch nicht
    local key = GuildKey()
    if not key then return end
    ns.db.motd = ns.db.motd or {}
    ns.db.motd[key] = text
end

function Info:MOTD()
    local key = GuildKey()
    if not IsInGuild() then return "" end
    local motd = self.current or (key and ns.db.motd and ns.db.motd[key])
    if not motd or ns.IsSecret(motd) then return "" end
    return motd
end

-- Gildeninformation (der Text aus dem Gildenfenster des Spiels). Dafür gibt es kein Ereignis, das den Text
-- mitbringt – er muss abgefragt werden. Die Abfrage ist eine der Funktionen, die das Spiel Addons zeitweise
-- oder ganz verwehrt. Deshalb: nur fragen, wenn gerade keine Sperre gilt, höchstens alle 30 Sekunden, und nie
-- wieder (bis zur nächsten Addon-Version), wenn das Spiel einmal abgelehnt hat. Gemerkt wird der Text pro Gilde.
local TEXT_EVERY = 30
local lastTextTry = -TEXT_EVERY

local function Restricted()
    if InCombatLockdown() then return true end
    local R = C_RestrictedActions
    if R and R.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
        for _, kind in pairs(Enum.AddOnRestrictionType) do
            local ok, active = pcall(R.IsAddOnRestrictionActive, kind)
            if ok and active then return true end
        end
    end
    return false
end

function Info:GuildText()
    local key = GuildKey()
    local text = key and ns.db.guildText and ns.db.guildText[key]
    if type(text) ~= "string" or ns.IsSecret(text) then return "" end
    return text
end

function Info:RefreshGuildText()
    local key = GuildKey()
    if not key or ns.db.settings.guildTextBlocked == ns.VERSION then return end
    if GetTime() - lastTextTry < TEXT_EVERY or Restricted() then return end
    lastTextTry = GetTime()
    local read = (C_GuildInfo and C_GuildInfo.GetInfoText) or GetGuildInfoText
    if type(read) ~= "function" then return end
    local ok, text = pcall(read)
    if not ok or type(text) ~= "string" or ns.IsSecret(text) then return end
    text = strtrim(text)
    -- Kurz nach dem Einloggen ist die Gildenliste noch nicht geladen und der Text leer: Gemerktes dann behalten
    if text == "" and not (ns.Members and #ns.Members.list > 0) then return end
    ns.db.guildText = ns.db.guildText or {}
    if ns.db.guildText[key] ~= text then
        ns.db.guildText[key] = text
        return true
    end
end

-- Lehnt das Spiel die Abfrage ab, meldet es das hier. Dann nicht weiter versuchen.
local function OnTextBlocked(addon, func)
    if addon ~= ADDON or GetTime() - lastTextTry > 2 then return end
    if type(func) == "string" and not func:find("InfoText", 1, true) then return end
    ns.db.settings.guildTextBlocked = ns.VERSION
end
pcall(ns.On, ns, "ADDON_ACTION_BLOCKED", OnTextBlocked)
pcall(ns.On, ns, "ADDON_ACTION_FORBIDDEN", OnTextBlocked)

-- Begrüßung einmal pro Account: beim ersten Start und nach dem Gildenbeitritt
function Info:MaybeWelcome()
    if not self:IsOurGuild() then return end
    local key = ns.PlayerKey()
    local seen = ns.db.welcomeSeen
    if not key or seen[key] then return end
    -- Einmal pro Account: Wer sie auf einem Charakter gesehen hat, bekommt sie auf Twinks nicht noch einmal
    local seenBefore = next(seen) ~= nil
    seen[key] = true
    if not seenBefore then ns.UI:Show("start") end
end

ns:On("PLAYER_LOGIN", function() C_Timer.After(6, function() Info:MaybeWelcome() end) end)
ns:On("PLAYER_GUILD_UPDATE", function() C_Timer.After(2, function() Info:MaybeWelcome() end) end)
ns:On("GUILD_MOTD", function(text)
    Info:SetMOTD(text)
    ns:Fire("INFO_UPDATE")
end)
