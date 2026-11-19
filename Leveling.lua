-- Elternabend: Stufenaufstiege der Gilde und die eigene Stufe-60-Prognose
--
-- Stufenaufstiege: Jeder Client vergleicht die Gildenliste mit dem gemerkten Stand und hält fest,
-- wer eine Stufe aufgestiegen ist („Keela 19 → 20“). Was passiert ist, während man selbst nicht
-- online war, steht mit dem Zeitpunkt, an dem es bemerkt wurde. Auf der Startseite unter „Aktuell“.
--
-- Prognose: Nur für dich, ohne Rangliste. Das Addon misst, wie viel Erfahrung du pro Spielstunde
-- sammelst (die letzten Spielstunden) und wie viel du im Schnitt pro Tag spielst (letzte zwei Wochen),
-- und rechnet daraus: „Stufe 60 etwa am 14.12.“. Gezählt wird nur Zeit, in der du nicht AFK bist.
local _, ns = ...

local Leveling = {}
ns.Leveling = Leveling

local MAX_LEVEL = 60
local KEEP_UPS = 60             -- so viele Stufenaufstiege bleiben gemerkt
local KEEP_UPS_DAYS = 14
local SAMPLE_EVERY = 300        -- alle 5 Spielminuten ein Messpunkt
local RATE_WINDOW = 10 * 3600   -- Erfahrung pro Stunde: über die letzten 10 Spielstunden
local MIN_PLAYED = 3600         -- so viel gemessene Spielzeit braucht die erste Prognose
local DAYS_WINDOW = 14

-- Erfahrung von Stufe n auf n+1 (klassisch, zusammen 4.084.700 von 1 bis 60)
Leveling.XP = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
    117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000,
    202300, 209800 }

-- Stufenaufstiege der Gilde --------------------------------------------------------------------
local function GuildStore()
    local guild = IsInGuild() and GetGuildInfo("player")
    if not guild or guild == "" or ns.IsSecret(guild) then return nil end
    ns.db.levelups = ns.db.levelups or {}
    ns.db.levelups[guild] = ns.db.levelups[guild] or { levels = {}, ups = {} }
    return ns.db.levelups[guild]
end

function Leveling:CheckGuild()
    local store = GuildStore()
    local list = ns.Members and ns.Members.list or {}
    if not store or #list == 0 then return end
    local known = 0
    for _ in pairs(store.levels) do known = known + 1 end
    -- Unvollständige Liste (Server lädt noch)? Dann lieber nichts folgern.
    if known > 10 and #list < known * 0.5 then return end
    local now, changed = time(), false
    for _, e in ipairs(list) do
        local level = tonumber(e.level)
        if e.key and level and level > 0 then
            local old = store.levels[e.key]
            if old and level > old and level - old <= 10 then
                table.insert(store.ups, 1, { t = now, name = e.name, class = e.classFile, from = old, to = level })
                changed = true
            end
            store.levels[e.key] = level
        end
    end
    local limit = now - KEEP_UPS_DAYS * 86400
    for i = #store.ups, 1, -1 do
        if i > KEEP_UPS or (store.ups[i].t or 0) < limit then table.remove(store.ups, i) end
    end
    if changed then ns:Fire("LEVELUP_UPDATE") end
end

function Leveling:Ups()
    local store = GuildStore()
    return store and store.ups or {}
end

-- „vor 5 Min.“, „vor 2 Std.“, „gestern“, „vor 3 Tagen“
function Leveling.Ago(t)
    local d = math.max(0, time() - (t or 0))
    if d < 90 then return "gerade eben" end
    if d < 3600 then return "vor " .. math.floor(d / 60 + 0.5) .. " Min." end
    if d < 86400 then return "vor " .. math.floor(d / 3600 + 0.5) .. " Std." end
    local days = math.floor(d / 86400 + 0.5)
    return days <= 1 and "gestern" or ("vor " .. days .. " Tagen")
end

ns:Listen("MEMBERS_UPDATE", function() Leveling:CheckGuild() end)

-- Eigene Prognose ------------------------------------------------------------------------------
local function CharStore()
    local key = ns.NameKey(ns.UnitFullName("player"))
    if not key then return nil end
    ns.db.leveling = ns.db.leveling or {}
    ns.db.leveling[key] = ns.db.leveling[key] or { samples = {}, days = {}, played = 0 }
    return ns.db.leveling[key]
end

-- Gesammelte Erfahrung seit Stufe 1
function Leveling.TotalXP(level, xp)
    local total = 0
    for i = 1, math.min((level or 1) - 1, #Leveling.XP) do total = total + Leveling.XP[i] end
    return total + (xp or 0)
end

local function Now()
    local level = UnitLevel("player") or 1
    return level, Leveling.TotalXP(level, UnitXP("player") or 0)
end

-- Jede Minute: Spielzeit mitzählen (nicht AFK) und alle 5 Spielminuten einen Messpunkt setzen
function Leveling:Tick(seconds)
    local s = CharStore()
    if not s then return end
    local level, xp = Now()
    if level >= MAX_LEVEL then return end
    if UnitIsAFK and UnitIsAFK("player") then return end
    s.played = (s.played or 0) + seconds
    local day = date("%Y-%m-%d")
    s.days[day] = (s.days[day] or 0) + seconds
    local last = s.samples[#s.samples]
    if not last or s.played - last.p >= SAMPLE_EVERY or xp < last.xp then
        if last and xp < last.xp then s.samples = {} end -- Charakter zurückgesetzt o. Ä.: neu anfangen
        table.insert(s.samples, { p = s.played, xp = xp })
    end
    -- alte Messpunkte und Tage wegräumen
    while #s.samples > 2 and s.played - s.samples[2].p > RATE_WINDOW do table.remove(s.samples, 1) end
    local oldest = date("%Y-%m-%d", time() - DAYS_WINDOW * 86400)
    for d in pairs(s.days) do
        if d < oldest then s.days[d] = nil end
    end
end

-- Prognose: { date = Zeitstempel, rate = Erfahrung pro Stunde, hours = Spielstunden pro Tag } oder nil
function Leveling:Forecast()
    local s = CharStore()
    if not s then return nil end
    local level, xp = Now()
    if level >= MAX_LEVEL then return { done = true } end
    local first = s.samples[1]
    if not first or (s.played or 0) - first.p < MIN_PLAYED then return { wait = true } end
    local gained = xp - first.xp
    local hours = ((s.played or 0) - first.p) / 3600
    if gained <= 0 or hours <= 0 then return { wait = true } end
    local rate = gained / hours
    -- Spielstunden pro Tag: über die Tage seit dem ersten gemessenen Tag (höchstens 14)
    local firstDay, total = nil, 0
    for d, sec in pairs(s.days) do
        total = total + sec
        if not firstDay or d < firstDay then firstDay = d end
    end
    local y, m, dd = (firstDay or ""):match("^(%d+)-(%d+)-(%d+)$")
    local start = y and time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }) or time()
    local spanDays = math.min(DAYS_WINDOW, math.max(1, math.floor((time() - start) / 86400) + 1))
    local perDay = total / 3600 / spanDays
    if perDay <= 0 then return { wait = true } end
    local remaining = Leveling.TotalXP(MAX_LEVEL, 0) - xp
    local days = remaining / (rate * perDay)
    return { date = time() + days * 86400, rate = rate, hours = perDay, level = level }
end

-- Eine Zeile für die Startseite
function Leveling:ForecastText()
    local f = self:Forecast()
    if not f then return "" end
    if f.done then return "" end
    if f.wait then return "Stufe-60-Prognose nach etwa einer Stunde Spielzeit." end
    local days = (f.date - time()) / 86400
    if days > 365 then return "Stufe 60: bei deinem Tempo noch über ein Jahr – ganz in Ruhe." end
    return string.format("Stufe 60 bei deinem Tempo etwa am %s", date("%d.%m.%Y", f.date))
        .. string.format(" (rund %s Std. am Tag)", (f.hours < 10 and string.format("%.1f", f.hours) or tostring(math.floor(f.hours + 0.5))):gsub("%.", ","))
end

ns:Listen("INIT", function()
    C_Timer.NewTicker(60, function() Leveling:Tick(60) end)
end)
