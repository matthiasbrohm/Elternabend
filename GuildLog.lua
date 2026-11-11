-- Elternabend: Gildenchronik für die Gildenleitung
--
-- Hält fest, was sich in der Gilde tut – nur bei Offizieren und Gildenleitung:
--   * Eintritte und Austritte (Vergleich der Gildenliste mit dem letzten gemerkten Stand)
--   * Rückkehrer: Spieler, die nach langer Pause (einstellbar, Standard 3 Monate) wieder online sind
--   * Rangänderungen und Charaktere, die Stufe 60 erreichen
-- Blizzards eigenes Gildenprotokoll (die letzten 100 Einträge) liefert dazu, wer eingeladen,
-- befördert oder entfernt hat – und füllt die Chronik beim ersten Start.
--
-- Gespeichert je Gilde in ns.db.guildlog[Gildenname]:
--   snapshot  key -> { name, rank, level, class, seen }   (seen = zuletzt online, Zeitstempel)
--   events    { t, type, name, class, … }  neueste zuerst
-- Die Chronik liegt nur auf dem eigenen Rechner; jeder Offizier führt seine eigene.
local _, ns = ...

local Log = {}
ns.GuildLog = Log

local MAX_EVENTS = 600
local MAX_LEVEL = 60
Log.THRESHOLDS = { 30, 60, 90, 180, 365 } -- Tage
Log.THRESHOLD_LABEL = { [30] = "1 Monat", [60] = "2 Monate", [90] = "3 Monate", [180] = "6 Monate", [365] = "1 Jahr" }

Log.TYPES = {
    join = { label = "Eintritt", color = "green" },
    leave = { label = "Austritt", color = "red" },
    back = { label = "Wieder da", color = "goldBright" },
    rank = { label = "Rang", color = "cream" },
    level = { label = "Stufe " .. MAX_LEVEL, color = "cream" },
}

local function Store()
    local guild = IsInGuild() and GetGuildInfo("player")
    if not guild or guild == "" then return nil end
    local all = ns.db.guildlog
    all[guild] = all[guild] or { snapshot = {}, events = {}, since = time() }
    return all[guild]
end
Log.Store = Store

function Log:Active()
    return ns.UI and ns.UI:IsLeader() or false
end

function Log:Threshold()
    return ns.db.settings.inactiveDays or 90
end

function Log:NextThreshold()
    local cur, list = self:Threshold(), self.THRESHOLDS
    local nextValue = list[1]
    for i, v in ipairs(list) do
        if v == cur then nextValue = list[i % #list + 1] end
    end
    ns.db.settings.inactiveDays = nextValue
    ns:Fire("GUILDLOG_UPDATE")
end

-- „3 Tage“, „5 Wochen“, „4 Monate“, „1 Jahr 2 Monate“
-- dative = true: für „vor …“ und „nach …“ („vor 3 Tagen“, „nach 4 Monaten“)
function Log.Duration(seconds, dative)
    local text = Log.DurationText(seconds)
    if dative then text = text:gsub("Tage$", "Tagen"):gsub("Monate", "Monaten"):gsub("Jahre", "Jahren") end
    return text
end

function Log.DurationText(seconds)
    local days = math.floor((seconds or 0) / 86400)
    if days < 1 then
        local hours = math.floor((seconds or 0) / 3600)
        return hours <= 1 and "1 Stunde" or (hours .. " Stunden")
    end
    if days < 14 then return days == 1 and "1 Tag" or (days .. " Tage") end
    if days < 60 then return math.floor(days / 7) .. " Wochen" end
    if days < 365 then return math.floor(days / 30) .. " Monate" end
    local years, months = math.floor(days / 365), math.floor((days % 365) / 30)
    return (years == 1 and "1 Jahr" or (years .. " Jahre")) .. (months > 0 and (" " .. months .. (months == 1 and " Monat" or " Monate")) or "")
end

local function Add(store, e)
    table.insert(store.events, 1, e)
    while #store.events > MAX_EVENTS do table.remove(store.events) end
end

-- Blizzards Gildenprotokoll ---------------------------------------------------------------
-- Liefert { type, who, by, rank, t } – neueste zuerst. Die Zeit ist nur „vor X Tagen/Stunden“.
function Log:BlizzardLog()
    local out = {}
    if not (GetNumGuildEvents and GetGuildEventInfo) then return out end
    local ok, n = pcall(GetNumGuildEvents)
    if not ok or type(n) ~= "number" then return out end
    for i = n, 1, -1 do
        local okInfo, kind, p1, p2, rank, year, month, day, hour = pcall(GetGuildEventInfo, i)
        if okInfo and kind and not ns.IsSecret(kind) and not ns.IsSecret(p1) then
            local ago = ((year or 0) * 365 + (month or 0) * 30 + (day or 0)) * 86400 + (hour or 0) * 3600
            local e = { type = kind, t = time() - ago, rank = rank }
            if kind == "join" or kind == "quit" then
                e.who = p1
            else
                e.by, e.who = p1, p2 -- invite, promote, demote, remove: p1 handelt, p2 ist betroffen
            end
            if e.who then table.insert(out, e) end
        end
    end
    return out
end

function Log:RequestBlizzardLog()
    if QueryGuildEventLog then pcall(QueryGuildEventLog) end
end

-- Zu einem Ereignis den passenden Eintrag aus Blizzards Protokoll suchen (wer hat es getan?)
local MATCH = {
    join = { invite = true },
    leave = { quit = true, remove = true },
    rank = { promote = true, demote = true },
}
local function Enrich(e, blizz)
    if e.by or e.how or not MATCH[e.type] then return false end
    for _, b in ipairs(blizz) do
        -- Das Ereignis lag zwischen dem letzten Abgleich und dem Entdecken (mit etwas Spielraum,
        -- Blizzards Zeiten sind auf Stunden gerundet)
        if MATCH[e.type][b.type] and ns.SameName(b.who, e.name)
            and b.t >= (e.since or e.t) - 2 * 86400 and b.t <= e.t + 86400 then
            if b.type == "quit" then
                e.how = "quit"
            else
                e.how = b.type
                e.by = b.by and ns.ShortName(b.by) or nil
            end
            -- Blizzards Zeit ist genauer als „beim Einloggen bemerkt“
            if e.since and e.t - e.since > 2 * 3600 and b.t < e.t then e.t = b.t end
            e.since = nil
            return true
        end
    end
    return false
end

-- Beim allerersten Start: die Chronik aus Blizzards Protokoll vorbelegen
local function Seed(store, blizz)
    if store.seeded then return false end
    store.seeded = true
    local invitedBy = {}
    for i = #blizz, 1, -1 do -- älteste zuerst
        local b = blizz[i]
        local name = b.who
        local m = ns.Members:Find(name)
        local class = m and m.classFile or nil
        if b.type == "invite" then
            invitedBy[ns.NameKey(name) or name] = b.by
        elseif b.type == "join" then
            local by = invitedBy[ns.NameKey(name) or name]
            Add(store, { t = b.t, type = "join", name = name, class = class, by = by and ns.ShortName(by) or nil, how = by and "invite" or nil, old = true })
        elseif b.type == "quit" then
            Add(store, { t = b.t, type = "leave", name = name, how = "quit", old = true })
        elseif b.type == "remove" then
            Add(store, { t = b.t, type = "leave", name = name, how = "remove", by = b.by and ns.ShortName(b.by) or nil, old = true })
        elseif b.type == "promote" or b.type == "demote" then
            Add(store, { t = b.t, type = "rank", name = name, class = class, to = b.rank, how = b.type, by = b.by and ns.ShortName(b.by) or nil, old = true })
        end
    end
    table.sort(store.events, function(a, b) return a.t > b.t end)
    return true
end

-- Vergleich mit dem gemerkten Stand ------------------------------------------------------
function Log:Check()
    if not self:Active() then return end
    local store = Store()
    local list = ns.Members.list
    if not store or #list == 0 then return end

    local known = 0
    for _ in pairs(store.snapshot) do known = known + 1 end
    -- Unvollständige Liste (Server lädt noch)? Dann lieber nichts folgern.
    if known > 10 and #list < known * 0.5 then return end

    local now = time()
    local first = known == 0
    local changed = false
    local since = store.checked or now -- Ereignisse sind irgendwann seit dem letzten Abgleich passiert
    local limit = self:Threshold() * 86400

    -- Wann war der Spieler (Main und Twinks zusammen) zuletzt da – nach dem alten Stand?
    local playerSeen = {}
    for _, e in ipairs(list) do
        local old = store.snapshot[e.key]
        local player = (e.main or e).key
        if old and old.seen then playerSeen[player] = math.max(playerSeen[player] or 0, old.seen) end
    end

    local present, greeted = {}, {}
    for _, e in ipairs(list) do
        present[e.key] = true
        local old = store.snapshot[e.key]
        local seen = e.online and now or (e.offline and (now - e.offline)) or (old and old.seen) or nil
        if not old then
            if not first then
                Add(store, { t = now, type = "join", name = e.name, class = e.classFile, level = e.level, since = since })
                changed = true
            end
        else
            if old.rank and e.rank and old.rank ~= e.rank then
                Add(store, { t = now, type = "rank", name = e.name, class = e.classFile, from = old.rank, to = e.rank, since = since })
                changed = true
            end
            if (old.level or 0) < MAX_LEVEL and (e.level or 0) >= MAX_LEVEL then
                Add(store, { t = now, type = "level", name = e.name, class = e.classFile })
                changed = true
            end
            -- Rückkehrer: gerade online, der ganze Spieler war aber lange weg
            local player = (e.main or e).key
            local last = playerSeen[player]
            if e.online and last and now - last > limit and not greeted[player] then
                greeted[player] = true
                Add(store, { t = now, type = "back", name = e.name, class = e.classFile, away = now - last })
                ns.Print(ns.Theme.Hex("goldBright", "Wieder da: ") .. ns.ShortName(e.name) .. " war " .. Log.Duration(now - last) .. " nicht online.")
                changed = true
            end
        end
        store.snapshot[e.key] = { name = e.name, rank = e.rank, level = e.level, class = e.classFile, seen = seen }
        -- (ein „gone“-Vermerk fällt damit weg: der Charakter ist wieder in der Liste)
    end

    -- Austritte: erst glauben, wenn jemand bei zwei Abgleichen (mindestens 30 Sekunden auseinander)
    -- fehlt – der Server liefert die Gildenliste manchmal kurz unvollständig
    for key, old in pairs(store.snapshot) do
        if present[key] then
            old.gone = nil
        elseif not old.gone then
            old.gone = now
            old.goneSince = since
        elseif now - old.gone >= 30 then
            Add(store, { t = old.gone, type = "leave", name = old.name, class = old.class, level = old.level, rank = old.rank, since = old.goneSince })
            store.snapshot[key] = nil
            changed = true
        end
    end

    store.checked = now
    if changed then
        self:RequestBlizzardLog() -- wer hat eingeladen / entfernt? kommt gleich nach
        ns:Fire("GUILDLOG_UPDATE")
    end
end

-- Blizzards Protokoll ist da: Chronik vorbelegen und frische Ereignisse ergänzen
function Log:OnBlizzardLog()
    if not self:Active() then return end
    local store = Store()
    if not store or #ns.Members.list == 0 then return end
    local blizz = self:BlizzardLog()
    if #blizz == 0 then return end
    local changed = Seed(store, blizz)
    local now = time()
    local enriched = false
    for _, e in ipairs(store.events) do
        if not e.old and e.since and now - e.t < 14 * 86400 and Enrich(e, blizz) then enriched = true end
    end
    if enriched then table.sort(store.events, function(a, b) return a.t > b.t end) end
    if changed or enriched then ns:Fire("GUILDLOG_UPDATE") end
end

-- Auswertungen für den Reiter --------------------------------------------------------------
function Log:Events(filter)
    local store = Store()
    local out = {}
    for _, e in ipairs(store and store.events or {}) do
        if not filter or e.type == filter then table.insert(out, e) end
    end
    return out
end

-- Ein Satz zum Ereignis
function Log.Describe(e)
    local T = ns.Theme
    if e.type == "join" then
        return "ist eingetreten" .. (e.by and (" – eingeladen von " .. e.by) or "") .. (e.level and (" (Stufe " .. e.level .. ")") or "")
    elseif e.type == "leave" then
        if e.how == "remove" then return "wurde entfernt" .. (e.by and (" von " .. e.by) or "") end
        return (e.how == "quit" and "ist ausgetreten" or "ist nicht mehr in der Gilde") .. (e.rank and (" (" .. e.rank .. (e.level and (", Stufe " .. e.level) or "") .. ")") or "")
    elseif e.type == "back" then
        return "ist wieder da – nach " .. Log.Duration(e.away, true)
    elseif e.type == "rank" then
        local verb = e.how == "demote" and "zurückgestuft" or (e.how == "promote" and "befördert" or "Rang geändert")
        return verb .. (e.from and (": " .. e.from .. " » " .. (e.to or "?")) or (e.to and (" zu " .. e.to) or "")) .. (e.by and (" – von " .. e.by) or "")
    elseif e.type == "level" then
        return T.Hex("goldBright", "hat Stufe " .. MAX_LEVEL .. " erreicht")
    end
    return ""
end

-- Spieler (Main mit Twinks), die länger als die Schwelle nicht online waren – längste zuerst
function Log:Inactive()
    local now, limit = time(), self:Threshold() * 86400
    local out = {}
    for _, m in ipairs(ns.Members.mains) do
        if not m.onlineAs then
            local away -- kürzeste Abwesenheit über alle Charaktere
            local function Look(e)
                if e.offline and (not away or e.offline < away) then away = e.offline end
            end
            Look(m)
            for _, t in ipairs(m.twinks) do Look(t) end
            if away and away > limit then table.insert(out, { member = m, away = away, last = now - away }) end
        end
    end
    table.sort(out, function(a, b) return a.away > b.away end)
    return out
end

function Log:Stats()
    local M = ns.Members
    local s = { chars = #M.list, players = #M.mains, online = 0, max = 0, joined = 0, left = 0, back = 0, classes = {}, since = nil }
    for _, m in ipairs(M.mains) do
        if m.onlineAs then s.online = s.online + 1 end
    end
    for _, e in ipairs(M.list) do
        if (e.level or 0) >= MAX_LEVEL then s.max = s.max + 1 end
        if e.class then s.classes[e.class] = (s.classes[e.class] or 0) + 1 end
    end
    local store = Store()
    local month = time() - 30 * 86400
    for _, e in ipairs(store and store.events or {}) do
        if e.t < month then break end
        if e.type == "join" then s.joined = s.joined + 1
        elseif e.type == "leave" then s.left = s.left + 1
        elseif e.type == "back" then s.back = s.back + 1 end
    end
    s.since = store and store.since
    s.inactive = #self:Inactive()
    return s
end

ns:Listen("MEMBERS_UPDATE", function() Log:Check() end)
ns:On("GUILD_EVENT_LOG_UPDATE", function() Log:OnBlizzardLog() end)
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(12, function()
        if IsInGuild() and Log:Active() then Log:RequestBlizzardLog() end
    end)
end)
